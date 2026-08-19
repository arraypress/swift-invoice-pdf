//
//  ValidatorTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  What a real validator found.
//
//  The XML this library writes was never put through one until now. It looked
//  right, it was well-formed, its figures agreed, and every test here passed
//  — and it would have been rejected. Five separate things, none of which a
//  test written from the same understanding that wrote the code could have
//  caught, because they were not misunderstandings of the standard so much as
//  parts of it nobody had read.
//
//  These are the findings, as tests. The validator itself is not run here —
//  it is Saxon and a hundred megabytes of published artefacts, which is not a
//  dependency a package should carry. `Scripts/validate-facturx.sh` fetches
//  the official schema and the profile rules and runs them properly; this
//  file is what stops the same five coming back between runs of it.
//

import Countries
import Foundation
import Money
import XCTest
@testable import InvoicePDF
import TextPDF

final class ValidatorTests: XCTestCase {

    private let issued = Date(timeIntervalSince1970: 1_785_000_000)

    private func invoice(
        vat: VatTreatment = .standard,
        seller: Country? = Country("GB"),
        buyer: Country? = Country("DE")
    ) -> Invoice {
        Invoice(
            branding: Branding(name: "Meridian Studio Ltd"),
            number: "INV-2026-0042",
            from: Party(name: "Meridian Studio Ltd", address: ["71 Shelton Street", "London"],
                        taxID: "GB123456789", country: seller),
            to: Party(name: "Klangwerk GmbH", address: ["Oranienburger Str. 87", "Berlin"],
                      taxID: "DE811567890", country: buyer),
            items: [LineItem(description: "Licence", amount: "£749.00")],
            totals: [("Subtotal", "£749.00")],
            vat: vat,
            reference: "PO-4471"
        )
    }

    private func details(
        profile: FacturX.Profile = .minimum,
        currency: String = "GBP",
        delivered: Date? = nil,
        deliveredTo: Country? = nil
    ) -> FacturX {
        FacturX(
            profile: profile, currency: currency, issued: issued,
            totals: .init(net: 749, tax: 149.80, gross: 898.80), taxRate: 20,
            delivered: delivered, deliveredTo: deliveredTo
        )
    }

    private func xml(_ invoice: Invoice, _ details: FacturX) throws -> String {
        String(data: try invoice.facturX(details), encoding: .utf8) ?? ""
    }

    // MARK: BR-09 — the country in the address

    func testTheSupplierCountryIsWrittenAndRequired() throws {
        // The first finding, and the one that would have failed every
        // document this library had ever produced: EN 16931 requires a
        // country in the seller's address, and there was nowhere to put one.
        let written = try xml(invoice(), details())
        XCTAssertTrue(written.contains("<ram:CountryID>GB</ram:CountryID>"), written)

        XCTAssertThrowsError(try xml(invoice(seller: nil), details())) {
            XCTAssertTrue("\($0)".contains("BR-09"), "\($0)")
        }
    }

    func testTheCountryIsNotGuessedFromTheAddress() {
        // It used to be read off the last address line where that line was
        // two capitals. That found nothing in "London WC2H 9JQ" — which is
        // why every document was invalid — and would have found Canada in
        // "Sacramento, CA".
        let sacramento = Party(name: "Widgets Inc", address: ["1 Main St", "Sacramento, CA"],
                               taxID: "US1", country: Country("US"))
        XCTAssertEqual(sacramento.country, Country("US"))
    }

    func testTheCustomerCountryIsRequiredOnlyWhereItIsCarried() throws {
        // Minimum does not carry the buyer's address at all, so it cannot
        // want a country in it. Basic WL does, and BR-11 applies there.
        XCTAssertNoThrow(try xml(invoice(buyer: nil), details(profile: .minimum)))

        XCTAssertThrowsError(
            try xml(invoice(buyer: nil), details(profile: .basicWithoutLines))
        ) {
            XCTAssertTrue("\($0)".contains("BR-11"), "\($0)")
        }
    }

    // MARK: The Minimum profile carries less than it was given

    func testMinimumLeavesOutWhatItIsNotAllowedToCarry() throws {
        // Two findings at once: Minimum permits neither the buyer's postal
        // address nor their tax registration, and a validator reports each
        // element that should not be there.
        let minimum = try xml(invoice(), details(profile: .minimum))
        let buyer = minimum.components(separatedBy: "<ram:BuyerTradeParty>")[1]
            .components(separatedBy: "</ram:BuyerTradeParty>")[0]

        XCTAssertFalse(buyer.contains("PostalTradeAddress"), buyer)
        XCTAssertFalse(buyer.contains("SpecifiedTaxRegistration"), buyer)
        XCTAssertTrue(buyer.contains("<ram:Name>Klangwerk GmbH</ram:Name>"), buyer)
    }

    func testBasicWithoutLinesCarriesBoth() throws {
        let basic = try xml(invoice(), details(profile: .basicWithoutLines))
        let buyer = basic.components(separatedBy: "<ram:BuyerTradeParty>")[1]
            .components(separatedBy: "</ram:BuyerTradeParty>")[0]

        XCTAssertTrue(buyer.contains("<ram:CountryID>DE</ram:CountryID>"), buyer)
        XCTAssertTrue(buyer.contains("<ram:ID schemeID=\"VA\">DE811567890</ram:ID>"), buyer)
    }

    // MARK: The order of the elements is part of the format

    func testTheTaxBlockIsInTheOrderTheSchemaDeclares() throws {
        // CII declares a sequence, so a reader stops at the first element out
        // of place. ExemptionReason was written after CategoryCode, which
        // reads naturally — the reason next to the code it explains — and is
        // rejected: the schema puts it third, before BasisAmount.
        let written = try xml(invoice(vat: .reverseCharge),
                              details(profile: .basicWithoutLines))

        // Only the tax block: `TypeCode` is also the document's own type at
        // the top of the file, and comparing against that one proves nothing.
        let tax = written.components(separatedBy: "<ram:ApplicableTradeTax>")[1]
            .components(separatedBy: "</ram:ApplicableTradeTax>")[0]

        let order = ["CalculatedAmount", "TypeCode", "ExemptionReason",
                     "BasisAmount", "CategoryCode", "RateApplicablePercent"]
        var last = -1
        for element in order {
            guard let at = tax.range(of: "<ram:\(element)>")?.lowerBound else {
                XCTFail("\(element) is missing from the tax block"); continue
            }
            let position = tax.distance(from: tax.startIndex, to: at)
            XCTAssertGreaterThan(position, last, "\(element) is out of sequence")
            last = position
        }
    }

    func testTheDeliveryBlockIsInSequenceToo() throws {
        // ShipToTradeParty comes before the delivery event, and both are
        // inside the delivery group rather than beside it.
        let written = try xml(
            invoice(vat: .intraCommunitySupply),
            details(profile: .basicWithoutLines, delivered: issued, deliveredTo: Country("DE"))
        )
        let delivery = written.components(separatedBy: "<ram:ApplicableHeaderTradeDelivery>")[1]
            .components(separatedBy: "</ram:ApplicableHeaderTradeDelivery>")[0]

        let shipTo = try XCTUnwrap(delivery.range(of: "<ram:ShipToTradeParty>"))
        let event = try XCTUnwrap(delivery.range(of: "<ram:ActualDeliverySupplyChainEvent>"))
        XCTAssertTrue(shipTo.lowerBound < event.lowerBound, delivery)
    }

    // MARK: BR-IC-11 and BR-IC-12 — evidencing a zero rate

    func testAnIntraCommunitySupplyCarriesWhereAndWhen() throws {
        // The zero rate rests on the goods having crossed a border on a date,
        // so the document has to say which border and what day. Without them
        // it claims a rate it does not evidence.
        let written = try xml(
            invoice(vat: .intraCommunitySupply),
            details(profile: .basicWithoutLines, delivered: issued, deliveredTo: Country("DE"))
        )

        XCTAssertTrue(written.contains("<ram:ActualDeliverySupplyChainEvent>"), written)
        XCTAssertTrue(written.contains("<udt:DateTimeString format=\"102\">20260725"), written)
        XCTAssertTrue(written.contains("<ram:ShipToTradeParty>"), written)
    }

    func testAnIntraCommunitySupplyWithoutADateIsRefused() {
        XCTAssertThrowsError(
            try xml(invoice(vat: .intraCommunitySupply), details(profile: .basicWithoutLines))
        ) {
            XCTAssertTrue("\($0)".contains("BR-IC-11"), "\($0)")
        }
    }

    func testTheDeliveryCountryFallsBackToTheCustomers() throws {
        // A delivery goes where the customer is unless somebody says
        // otherwise, so BR-IC-12 is satisfied without asking twice.
        let written = try xml(
            invoice(vat: .intraCommunitySupply),
            details(profile: .basicWithoutLines, delivered: issued)
        )
        let delivery = written.components(separatedBy: "<ram:ApplicableHeaderTradeDelivery>")[1]
        XCTAssertTrue(delivery.contains("<ram:CountryID>DE</ram:CountryID>"), delivery)
    }

    func testAnOrdinaryInvoiceNeedsNoneOfIt() throws {
        // Nothing in the delivery group is required on a domestic invoice,
        // and the Minimum profile has no delivery group at all.
        XCTAssertTrue(try xml(invoice(), details(profile: .minimum))
            .contains("<ram:ApplicableHeaderTradeDelivery/>"))
        XCTAssertNoThrow(try xml(invoice(), details(profile: .basicWithoutLines)))
    }

    // MARK: BR-DEC — two decimals, whatever the currency has

    func testACurrencyWithThreeDecimalsCannotBeAnEInvoice() {
        // The finding that contradicted what this library documented. Every
        // document-level amount is capped at two decimals — BR-DEC-09 through
        // BR-DEC-20 — whatever the currency's own minor unit is. The dinar
        // has three, so the standard has nowhere to put a fils.
        for code in ["KWD", "BHD", "OMR", "TND", "JOD", "IQD", "LYD"] {
            XCTAssertThrowsError(try xml(invoice(), details(currency: code)), code) {
                XCTAssertTrue("\($0)".contains("BR-DEC"), "\(code): \($0)")
                XCTAssertTrue("\($0)".contains(code), "\(code): \($0)")
            }
        }
    }

    func testACurrencyWithFourDecimalsCannotEither() {
        for code in ["CLF", "UYW"] {
            XCTAssertThrowsError(try xml(invoice(), details(currency: code)), code)
        }
    }

    func testTheOnesThatFitStillGoThrough() throws {
        // Nought and two both fit inside two, so the yen and the pound are
        // unaffected — the refusal is narrow, not a retreat from currencies.
        for code in ["GBP", "EUR", "USD", "JPY", "KRW", "ISK", "SEK"] {
            XCTAssertNoThrow(try xml(invoice(), details(currency: code)), code)
        }
    }

    func testTheRefusalSaysWhatToDoAboutIt() {
        // A refusal that names the rule is one somebody can check; a refusal
        // that names the currency is one somebody can act on.
        XCTAssertThrowsError(try xml(invoice(), details(currency: "KWD"))) {
            let said = "\($0)"
            XCTAssertTrue(said.contains("3 decimal places"), said)
            XCTAssertTrue(said.contains("EN 16931 allows two"), said)
        }
    }
}
