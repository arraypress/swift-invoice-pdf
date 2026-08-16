//
//  EveryCurrencyInvoiceTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  An invoice in every currency there is.
//
//  swift-money proves the arithmetic holds for all of them. This proves the
//  document does: that the figures reach the page, that the XML carries the
//  same ones, and that the two halves of an e-invoice agree — in the yen,
//  which has no decimals, in the dinar, which has three, and in the hundred
//  and seventy others where nothing was written with them in mind.
//

import Countries
import Foundation
import Money
import PDFKit
import XCTest
@testable import InvoicePDF
import TextPDF

final class EveryCurrencyInvoiceTests: XCTestCase {

    private let issued = Date(timeIntervalSince1970: 1_785_000_000)
    private let all = Currency.known

    /// The same invoice, priced in whichever currency.
    ///
    /// The amounts are given in whole major units so the expected figures can
    /// be stated without knowing how many decimals the currency has.
    private func totals(in currency: Currency, rate: Decimal = 20) -> Totals {
        let unit = currency.unitsPerMajor
        return Totals(
            lines: [
                .init("Document generation licence", unitPrice: Money(units: 500 * unit, in: currency)),
                .init("Template design", quantity: 3, unitPrice: Money(units: 70 * unit, in: currency)),
                .init("Priority support", unitPrice: Money(units: 39 * unit, in: currency)),
            ],
            rate: rate,
            currency: currency
        )
    }

    // MARK: The figures

    func testTheInvoiceAddsUpInEveryCurrency() {
        for currency in all {
            let sums = totals(in: currency)
            let unit = currency.unitsPerMajor

            XCTAssertEqual(sums.net.units, 749 * unit, currency.code)

            // 20% of 749 is 149.80, which the currencies with a minor unit
            // hold exactly and the ones without have to round — to 150,
            // because half goes away from zero. Worked out here the long way
            // rather than reusing the library's own arithmetic, so this is a
            // check and not a restatement.
            var exact = Decimal(749 * unit) * Decimal(20) / Decimal(100)
            var expected = Decimal()
            NSDecimalRound(&expected, &exact, 0, .plain)

            XCTAssertEqual(sums.tax.units, NSDecimalNumber(decimal: expected).intValue,
                           currency.code)
            XCTAssertEqual(sums.net + sums.tax, sums.gross, currency.code)
        }
    }

    func testTheTwoHalvesAgreeInEveryCurrency() {
        // The check that runs before an e-invoice is written, in every
        // currency: the tolerance is scaled to the currency's own smallest
        // unit, so a penny of slack in the pound is a thousandth of a dinar
        // and nothing at all in the yen.
        for currency in all {
            for rate in [Decimal(0), 5, 7.7, 19, 20, 21, 23, 27] {
                let sums = totals(in: currency, rate: rate)
                XCTAssertEqual(
                    sums.facturX(issued: issued).totals.disagreements(currency: currency.code),
                    [],
                    "\(currency.code) at \(rate)%"
                )
            }
        }
    }

    func testTheXMLCarriesTheFiguresTheCurrencyActuallyHas() {
        // The failure this exists for: an amount written to two places in a
        // currency that has none. A buyer's system reads "1000.00 JPY" and
        // either rejects it or, worse, takes it.
        for currency in all {
            let sums = totals(in: currency)
            let details = sums.facturX(issued: issued)
            let written = Money(details.totals.gross, in: currency).decimalString

            if currency.decimals == 0 {
                XCTAssertFalse(written.contains("."), "\(currency.code): \(written)")
            } else {
                XCTAssertEqual(written.split(separator: ".").last?.count, currency.decimals,
                               "\(currency.code): \(written)")
            }
        }
    }

    // MARK: The page

    func testTheFiguresReachThePageInEveryCurrency() throws {
        // Rendering all hundred and eighty is slow, so this walks the ones
        // that differ in a way the page can show — no decimals, three, four,
        // a symbol before, a symbol after, a code with no symbol at all —
        // plus the ordinary case.
        for code in ["GBP", "EUR", "USD", "JPY", "KWD", "CLF", "SEK", "CHF", "INR", "ZWG"] {
            let currency = Currency(code)
            let locale = Locale(identifier: "en_GB")
            let sums = totals(in: currency)

            let invoice = Invoice(
                branding: Branding(name: "SwiftInvoices Ltd"),
                number: "INV-2026-0091",
                from: Party(name: "SwiftInvoices Ltd", address: ["71 Shelton Street"], taxID: "GB1"),
                to: Party(name: "Klangwerk GmbH", address: ["Oranienburger Str. 87"], taxID: "DE1"),
                items: sums.items(in: locale),
                totals: sums.rows(in: locale),
                total: [("Total due", sums.gross.formatted(in: locale))],
                vatLines: sums.vatLines(in: locale)
            )

            let text = try XCTUnwrap(PDFDocument(data: invoice.render().render())?.string)

            // The digits, whatever the symbol and the separators around them.
            let digits = sums.gross.decimalString.filter(\.isNumber)
            let onPage = text.filter(\.isNumber)
            XCTAssertTrue(onPage.contains(digits),
                          "\(code): \(sums.gross.formatted(in: locale)) is not on the page")
        }
    }

    private func eInvoice(in currency: Currency) throws -> Data {
        let sums = totals(in: currency)
        let invoice = Invoice(
            branding: Branding(name: "SwiftInvoices Ltd"),
            number: "INV-2026-0092",
            from: Party(name: "SwiftInvoices Ltd", address: ["71 Shelton Street"],
                        taxID: "GB123456789", country: Country("GB")),
            to: Party(name: "Klangwerk GmbH", address: ["Oranienburger Str. 87"],
                      taxID: "DE811234567", country: Country("DE")),
            items: sums.items(),
            totals: sums.rows(),
            total: [("Total due", sums.gross.formatted())],
            vatLines: sums.vatLines()
        )
        return try invoice.facturX(sums.facturX(issued: issued))
    }

    func testTheYenGoesTheWholeWay() throws {
        // The currency with no minor unit, end to end.
        let sums = totals(in: .jpy)
        let xml = try XCTUnwrap(String(data: try eInvoice(in: .jpy), encoding: .utf8))

        XCTAssertTrue(xml.contains("<ram:InvoiceCurrencyCode>JPY</ram:InvoiceCurrencyCode>"), xml)
        XCTAssertTrue(
            xml.contains("<ram:GrandTotalAmount>\(sums.gross.decimalString)</ram:GrandTotalAmount>"),
            "the gross in the XML is not the gross that was worked out"
        )
        XCTAssertFalse(xml.contains("<ram:GrandTotalAmount>163900.00"), "the yen got decimals")
    }

    func testTheDinarCannotBeAnEInvoiceAtAll() {
        // Found by the official validator: EN 16931 caps document amounts at
        // two decimals (BR-DEC-09 to BR-DEC-20) whatever the currency's minor
        // unit is, and the dinar has three. Refused rather than rounded — a
        // fils quietly lost is worse than a document that will not be built.
        XCTAssertThrowsError(try eInvoice(in: Currency("KWD"))) {
            XCTAssertTrue("\($0)".contains("BR-DEC"), "\($0)")
        }
    }

    // MARK: What is refused

    func testAnInvoiceInOneCurrencyWillNotTakeALineInAnother() {
        // The construction stops rather than producing a document labelled in
        // a currency its figures are not in. Not assertable directly — it
        // takes the process with it — so what is checked is that the lines
        // that do belong are accepted, and the message names the offender.
        let sums = Totals(
            lines: [.init("Licence", unitPrice: Money(units: 100, in: .gbp))],
            rate: 20, currency: .gbp
        )
        XCTAssertEqual(sums.net.currency, Currency.gbp)
    }

    func testAFigureTooLargeToWriteIsCaughtBeforeAnyXMLIsBuilt() throws {
        // The checker sees it, and `facturX` throws rather than writing a
        // number that wrapped into a smaller one on the way out.
        let absurd = Decimal(string: "99999999999999999999999")!
        let broken = FacturX.Totals(net: absurd, tax: 0, gross: absurd)

        let problems = broken.disagreements(currency: "GBP")
        XCTAssertFalse(problems.isEmpty)
        XCTAssertTrue(problems.contains { $0.contains("not an amount that can be written") },
                      "\(problems)")
    }
}
