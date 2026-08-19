//
//  TotalsTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//

import Countries
import Foundation
import Money
import PDFKit
import XCTest
@testable import InvoicePDF
import TextPDF

final class TotalsTests: XCTestCase {

    private let issued = Date(timeIntervalSince1970: 1_785_000_000)

    private func totals(rate: Decimal = 20, currency: Currency = .gbp) -> Totals {
        Totals(
            lines: [
                .init("Document generation licence", unitPrice: Money("149.00", in: currency)!),
                .init("Template design and setup", quantity: 6,
                      unitPrice: Money("70.00", in: currency)!),
                .init("Priority support", unitPrice: Money("180.00", in: currency)!),
            ],
            rate: rate,
            currency: currency
        )
    }

    // MARK: The arithmetic

    func testTheLinesAddUp() {
        // 149 + 420 + 180.
        XCTAssertEqual(totals().net.decimalString, "749.00")
    }

    func testTheTaxIsTakenOnTheTotal() {
        XCTAssertEqual(totals().tax.decimalString, "149.80")
        XCTAssertEqual(totals().gross.decimalString, "898.80")
    }

    func testTheTotalsAlwaysAgree() {
        // The reason this type exists: nobody writes the figures twice, so
        // nothing can be written twice differently.
        for rate in [Decimal(0), 5, 19, 20, 21, 23, 27] {
            let sums = totals(rate: rate)
            XCTAssertEqual(sums.net + sums.tax, sums.gross, "at \(rate)%")
        }
    }

    func testNoRateMeansNoTax() {
        let sums = totals(rate: 0)
        XCTAssertEqual(sums.tax.decimalString, "0.00")
        XCTAssertEqual(sums.gross, sums.net)
        XCTAssertTrue(sums.vatLines().isEmpty)
        XCTAssertEqual(sums.rows().count, 1, "a VAT row with nothing in it is a row too many")
    }

    func testNoLines() {
        let empty = Totals(lines: [], rate: 20, currency: .gbp)
        XCTAssertEqual(empty.net.decimalString, "0.00")
        XCTAssertEqual(empty.gross.decimalString, "0.00")
    }

    // MARK: The two halves cannot disagree

    func testThePageAndTheXMLCarryTheSameFigures() throws {
        let sums = totals()
        let details = sums.facturX(issued: issued)

        XCTAssertEqual(details.totals.net, sums.net.decimal)
        XCTAssertEqual(details.totals.tax, sums.tax.decimal)
        XCTAssertEqual(details.totals.gross, sums.gross.decimal)

        // And the figures the checker looks at agree with each other.
        XCTAssertEqual(details.totals.disagreements(currency: "GBP"), [])
    }

    func testTheWholeDocumentIsBuiltFromOneSetOfNumbers() throws {
        let sums = totals()
        let invoice = Invoice(
            branding: Branding(name: "Meridian Studio Ltd"),
            number: "INV-2026-0044",
            from: Party(name: "Meridian Studio Ltd", address: ["71 Shelton Street"], taxID: "GB1",
                        country: Country("GB")),
            to: Party(name: "Klangwerk GmbH", address: ["Oranienburger Str. 87"], taxID: "DE1",
                      country: Country("DE")),
            items: sums.items(in: Locale(identifier: "en_GB")),
            totals: sums.rows(in: Locale(identifier: "en_GB")),
            total: [("Total due", sums.gross.formatted(in: Locale(identifier: "en_GB")))],
            vatLines: sums.vatLines(in: Locale(identifier: "en_GB")),
            supplyDate: "31 July 2026"
        )

        let text = try XCTUnwrap(PDFDocument(data: invoice.render().render())?.string)

        XCTAssertTrue(text.contains("£749.00"), "the subtotal is not on the page")
        XCTAssertTrue(text.contains("£149.80"), "the VAT is not on the page")
        XCTAssertTrue(text.contains("£898.80"), "the total is not on the page")

        // The same numbers, in the machine-readable half.
        let xml = try XCTUnwrap(String(data: try invoice.facturX(sums.facturX(issued: issued)),
                                       encoding: .utf8))
        XCTAssertTrue(xml.contains("<ram:LineTotalAmount>749.00</ram:LineTotalAmount>"), xml)
        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>898.80</ram:GrandTotalAmount>"), xml)
    }

    // MARK: Currencies that are not the pound

    func testTheYenAddsUpInWholeYen() {
        let yen = Totals(
            lines: [.init("ライセンス", unitPrice: Money("149000", in: .jpy)!)],
            rate: 10, currency: .jpy
        )

        XCTAssertEqual(yen.net.decimalString, "149000")
        XCTAssertEqual(yen.tax.decimalString, "14900")
        XCTAssertEqual(yen.gross.decimalString, "163900")
        XCTAssertEqual(yen.facturX(issued: issued).totals.disagreements(currency: "JPY"), [])
    }

    func testADinarKeepsItsThirdDecimal() {
        let dinar = Totals(
            lines: [.init("Licence", unitPrice: Money("1.234", in: Currency("KWD"))!)],
            rate: 0, currency: Currency("KWD")
        )
        XCTAssertEqual(dinar.net.decimalString, "1.234")
    }

    func testARateThatDoesNotDivideEvenly() {
        // 23% of 749.00 is 172.27, and the three figures still agree.
        let sums = totals(rate: 23)
        XCTAssertEqual(sums.tax.decimalString, "172.27")
        XCTAssertEqual(sums.net + sums.tax, sums.gross)
        XCTAssertEqual(sums.facturX(issued: issued).totals.disagreements(currency: "GBP"), [])
    }

    func testTheRateIsWrittenTheWayPeopleWriteIt() {
        XCTAssertEqual(Totals.percentage(20), "20")
        XCTAssertEqual(Totals.percentage(Decimal(string: "19.5")!), "19.5")
        XCTAssertEqual(totals(rate: 20).rows().last?.label, "VAT at 20%")
    }
}
