//
//  SellerBlockTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The supplier's name, address and VAT number are mandatory particulars,
//  and for a long time the template never drew them — while every compliance
//  check passed, because each one asked whether the fields were set. These
//  read the rendered page, as a recipient would.
//

import Foundation
import PDFKit
import XCTest
import TextPDF
@testable import InvoicePDF

final class SellerBlockTests: XCTestCase {

    // Every particular distinct from anything else on the page, so finding
    // one proves where it came from.
    private let seller = Party(
        name: "Lachlan Weaving Ltd",
        address: ["14 Thistle Wynd", "Dunfermline KY12 7QP"],
        email: "accounts@lachlanweaving.example",
        taxID: "IE1234567X",
        registration: "Company no. SC612345"
    )
    private let buyer = Party(
        name: "Hafenkontor GmbH",
        address: ["Speicherstadt 9", "20457 Hamburg"],
        taxID: "DE811567890"
    )

    private func invoice(kind: DocumentKind = .invoice, from: Party? = nil,
                         details: [(label: String, value: String)] = [("Issued", "1 August 2026")]) -> Invoice {
        Invoice(
            kind: kind,
            branding: Branding(name: "Lachlan"),
            number: "INV-7731",
            from: from ?? seller, to: buyer,
            items: [LineItem(description: "Tweed, 40 m", amount: "£1,200.00")],
            totals: [("Subtotal", "£1,200.00"), ("VAT (20%)", "£240.00")],
            total: [("Total due", "£1,440.00")],
            details: details,
            supplyDate: "28 July 2026",
            reference: kind == .creditNote || kind == .debitNote ? "INV-7700" : ""
        )
    }

    /// The page as a PDF reader extracts it — what the recipient sees.
    private func pageText(_ invoice: Invoice) throws -> String {
        try XCTUnwrap(PDFDocument(data: invoice.render().render())?.string)
    }

    // MARK: Drawn

    func testTheSellerIsPrintedOnTheInvoice() throws {
        let text = try pageText(invoice())

        XCTAssertTrue(text.contains("FROM"))
        for particular in ["Lachlan Weaving Ltd", "14 Thistle Wynd", "Dunfermline KY12 7QP",
                           "accounts@lachlanweaving.example", "VAT IE1234567X", "Company no. SC612345"] {
            XCTAssertTrue(text.contains(particular), "\"\(particular)\" is not on the page")
        }
        // The buyer and the details are still beside it.
        for particular in ["BILLED TO", "Hafenkontor GmbH", "Speicherstadt 9", "VAT DE811567890",
                           "DETAILS", "28 July 2026"] {
            XCTAssertTrue(text.contains(particular), "\"\(particular)\" is not on the page")
        }
    }

    func testEveryKindPrintsItsIssuer() throws {
        for kind in DocumentKind.allCases {
            let text = try pageText(invoice(kind: kind))
            for particular in ["Lachlan Weaving Ltd", "14 Thistle Wynd", "IE1234567X"] {
                XCTAssertTrue(text.contains(particular), "\(kind): \"\(particular)\" is not on the page")
            }
        }
    }

    func testWithoutDetailsTheTwoPartiesStillPrint() throws {
        let text = try pageText(invoice(details: []))
        XCTAssertTrue(text.contains("IE1234567X"))
        XCTAssertTrue(text.contains("DE811567890"))
    }

    func testTheHeadingsSayWhoIssuedIt() throws {
        // On a self-billed invoice the customer issues it; headed "FROM" and
        // "BILLED TO" the blocks would read the wrong way round.
        XCTAssertEqual(invoice(kind: .selfBilling).fromHeading, "CUSTOMER")
        XCTAssertEqual(invoice(kind: .selfBilling).toHeading, "SUPPLIER")
        XCTAssertEqual(invoice(kind: .purchaseOrder).fromHeading, "BUYER")
        XCTAssertEqual(invoice().fromHeading, "FROM")
        XCTAssertEqual(invoice().toHeading, "BILLED TO")

        let text = try pageText(invoice(kind: .selfBilling))
        XCTAssertTrue(text.contains("CUSTOMER"))
        XCTAssertTrue(text.contains("SUPPLIER"))
    }

    func testALongAddressWrapsRatherThanBeingCut() throws {
        let long = Party(
            name: "Lachlan Weaving Ltd",
            address: ["Unit 14B, Pitreavie Business Park, Queensferry Road", "Dunfermline KY11 8UU"],
            taxID: "IE1234567X"
        )
        let wrapped = invoice(from: long)
        let document = try wrapped.render()

        // Wrapped, so no single run holds the whole line ...
        XCTAssertFalse(document.drawnText.contains(long.address[0]))
        // ... nothing was cut with an ellipsis ...
        XCTAssertFalse(document.drawnText.contains { $0.hasSuffix("...") })
        // ... and the check still finds it on the page.
        XCTAssertEqual(wrapped.complianceWarnings(verifying: document), [])
    }

    // MARK: Checked

    func testARenderedInvoicePassesTheDrawnCheck() throws {
        for kind in DocumentKind.allCases where kind.isTaxDocument {
            let invoice = invoice(kind: kind)
            XCTAssertEqual(invoice.complianceWarnings(verifying: try invoice.render()), [], "\(kind)")
        }
    }

    func testTheCheckFlagsASellerThatNeverReachedThePage() throws {
        // What the template used to draw: the buyer, the details and the
        // figures, and nothing of the supplier but the brand name.
        let invoice = invoice()
        let page = Document(size: .a4, margin: 48)
        for text in ["LACHLAN", "INVOICE", "INV-7731", "BILLED TO", "Hafenkontor GmbH",
                     "Speicherstadt 9", "20457 Hamburg", "VAT DE811567890",
                     "28 July 2026", "£1,440.00"] {
            page.textAt(text, x: 48, y: 400, size: 9)
        }

        let warnings = invoice.complianceWarnings(verifying: page)
        XCTAssertTrue(invoice.complianceWarnings().isEmpty, "the data is complete; only the page is not")
        XCTAssertTrue(warnings.contains { $0.contains("Lachlan Weaving Ltd") && $0.contains("name") })
        XCTAssertTrue(warnings.contains { $0.contains("14 Thistle Wynd") })
        XCTAssertTrue(warnings.contains { $0.contains("Dunfermline KY12 7QP") })
        XCTAssertTrue(warnings.contains { $0.contains("IE1234567X") })
        XCTAssertTrue(warnings.contains { $0.contains("Company no. SC612345") })
        XCTAssertFalse(warnings.contains { $0.contains("Hafenkontor") }, "the buyer was drawn")
    }

    func testTheCheckFlagsABuyerThatNeverReachedThePage() throws {
        let invoice = invoice()
        let page = Document(size: .a4, margin: 48)
        for text in ["INV-7731", "Lachlan Weaving Ltd", "14 Thistle Wynd", "Dunfermline KY12 7QP",
                     "VAT IE1234567X", "Company no. SC612345", "28 July 2026", "£1,440.00"] {
            page.textAt(text, x: 48, y: 400, size: 9)
        }
        let warnings = invoice.complianceWarnings(verifying: page)
        XCTAssertTrue(warnings.contains { $0.contains("Speicherstadt 9") })
        XCTAssertTrue(warnings.contains { $0.contains("DE811567890") })
        XCTAssertFalse(warnings.contains { $0.contains("IE1234567X") })
    }

    func testAQuoteIsNotHeldToThePartyCheck() throws {
        // Not a tax document, so the particulars are not demanded of it.
        let quote = invoice(kind: .quote)
        let warnings = quote.complianceWarnings(verifying: Document(size: .a4, margin: 48))
        XCTAssertFalse(warnings.contains { $0.contains("Lachlan") || $0.contains("Hafenkontor") })
    }

    // MARK: The matching rule

    func testMatchingIgnoresWhereALineWasWrapped() {
        let page = DrawnParticulars.page(["Unit 14B, Pitreavie", "Business Park", "accounts@lachlanwe", "aving.example"])
        XCTAssertTrue(DrawnParticulars.shows("Unit 14B, Pitreavie Business Park", on: page))
        XCTAssertTrue(DrawnParticulars.shows("accounts@lachlanweaving.example", on: page))
        XCTAssertFalse(DrawnParticulars.shows("IE1234567X", on: page))
        XCTAssertTrue(DrawnParticulars.shows("  ", on: page), "nothing to print is nothing missing")
    }

    func testOnlyWhatWasSetIsDemanded() {
        let missing = DrawnParticulars.missing(name: "S", address: [], taxID: "", registration: "",
                                               on: DrawnParticulars.page(["S"]))
        XCTAssertEqual(missing, [])
    }

    // MARK: The model

    func testAPartyWrittenBeforeRegistrationExistedStillDecodes() throws {
        let json = #"{"name":"S","address":["1 Road"],"email":"","taxID":"GB1"}"#
        let party = try JSONDecoder().decode(Party.self, from: Data(json.utf8))
        XCTAssertNil(party.registration)
        XCTAssertEqual(party.lines(), ["1 Road", "VAT GB1"])
    }

    func testRegistrationIsPrintedAsWritten() {
        let party = Party(name: "S", address: ["1 Road"], taxID: "GB1", registration: "HRB 12345 B")
        XCTAssertEqual(party.lines(), ["1 Road", "VAT GB1", "HRB 12345 B"])
    }
}
