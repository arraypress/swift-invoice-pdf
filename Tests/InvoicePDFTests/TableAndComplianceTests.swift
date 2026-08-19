//
//  TableAndComplianceTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Moved out of swift-text-pdf when the templates were: these exercise a
//  document rather than the writer under it, and they were only living there
//  because the templates were.
//

import PDFKit
import XCTest
import TextPDF
@testable import InvoicePDF

final class TableAndComplianceTests: XCTestCase {

    // MARK: - Compliance

    private func minimalInvoice(kind: DocumentKind = .invoice, reference: String = "") -> Invoice {
        Invoice(
            kind: kind,
            branding: Branding(name: "Test"),
            number: "INV-1",
            from: Party(name: "Seller", address: ["1 Road"], taxID: "GB1"),
            to: Party(name: "Buyer", address: ["2 Road"]),
            items: [LineItem(description: "Thing", amount: "£1.00")],
            totals: [("Subtotal", "£1.00")],
            supplyDate: "1 August 2026",
            reference: reference
        )
    }

    func testMissingSupplyDateIsCaught() {
        // The particular most often left off, and a §14 UStG requirement.
        let invoice = Invoice(
            branding: Branding(name: "T"), number: "INV-1",
            from: Party(name: "S", address: ["1"], taxID: "GB1"),
            to: Party(name: "B", address: ["2"]),
            items: [], totals: [("Subtotal", "£1")]
        )
        XCTAssertTrue(invoice.complianceWarnings().contains { $0.contains("date of supply") })
    }

    func testReverseChargeDemandsTheCustomerVatNumber() {
        let invoice = Invoice(
            branding: Branding(name: "T"), number: "INV-1",
            from: Party(name: "S", address: ["1"], taxID: "GB1"),
            to: Party(name: "B", address: ["2"]),
            items: [], totals: [("Net", "£1")],
            vat: .reverseCharge, supplyDate: "1 Aug"
        )
        XCTAssertTrue(invoice.complianceWarnings().contains { $0.contains("customer VAT number") })
    }

    func testSelfBillingWordingAppears() {
        // Without the words on the face of it the recipient cannot rely on it.
        XCTAssertTrue(DocumentKind.selfBilling.standingNote?.contains("Self-billing") ?? false)
    }

    func testRemittanceIsNotATaxDocument() {
        // It reports payment against someone else's invoice; the particulars
        // belong on theirs.
        let advice = Invoice(
            kind: .remittance, branding: Branding(name: "T"), number: "RA-1",
            from: Party(name: "S"), to: Party(name: "B"), items: []
        )
        XCTAssertTrue(advice.complianceWarnings().isEmpty)
        XCTAssertEqual(DocumentKind.remittance.title, "REMITTANCE ADVICE")
    }

    func testDeliveryNoteShowsNoMoney() throws {
        // It travels with the goods; the warehouse has no business seeing the
        // price. Suppressing the columns is the document's defining behaviour.
        XCTAssertFalse(DocumentKind.deliveryNote.showsMoney)
        XCTAssertTrue(DocumentKind.invoice.showsMoney)

        let note = Invoice(
            kind: .deliveryNote, branding: Branding(name: "T"), number: "DN-1",
            from: Party(name: "S"), to: Party(name: "B"),
            items: [LineItem(description: "Widget", amount: "£99.00", quantity: "3", unitPrice: "£33.00")],
            totals: [("Subtotal", "£99.00")], total: [("Total", "£99.00")]
        )
        let stream = String(decoding: try note.render().render(), as: UTF8.self)
        XCTAssertFalse(stream.contains("99.00"), "a price reached a delivery note")
        XCTAssertTrue(stream.contains("(Widget) Tj"))
    }

    func testSingleRateBreakdownIsOmittedAsRedundant() {
        // One standard rate repeats the totals block verbatim — the same two
        // figures, in a column that lines up with nothing.
        func invoice(_ lines: [VatLine], vat: VatTreatment = .standard) -> Invoice {
            Invoice(
                branding: Branding(name: "T"), number: "INV-1",
                from: Party(name: "S", address: ["1"], taxID: "GB1"),
                to: Party(name: "B", address: ["2"], taxID: "GB2"),
                items: [LineItem(description: "Thing", amount: "£10")],
                totals: [("Subtotal", "£10")], vat: vat, vatLines: lines, supplyDate: "1 Aug"
            )
        }
        let one = [VatLine(rate: "20%", net: "£10", vat: "£2")]
        let two = one + [VatLine(rate: "5%", net: "£4", vat: "£0.20")]

        XCTAssertFalse(invoice(one).showsVatBreakdown)
        XCTAssertTrue(invoice(two).showsVatBreakdown, "mixed rates are the case the law requires")
        XCTAssertTrue(
            invoice(one, vat: .reverseCharge).showsVatBreakdown,
            "the row is what evidences a zero rating"
        )
    }

    func testAQuoteIsNotHeldToTaxRules() {
        // Demanding a supply date on a quotation would be a false warning.
        let quote = Invoice(
            kind: .quote, branding: Branding(name: "T"), number: "Q-1",
            from: Party(name: "S"), to: Party(name: "B"), items: []
        )
        XCTAssertTrue(quote.complianceWarnings().isEmpty)
    }

    func testGermanWordingIsAddedOnlyWhenAsked() {
        XCTAssertEqual(VatTreatment.reverseCharge.notes().count, 2)
        XCTAssertEqual(VatTreatment.reverseCharge.notes(german: true).count, 3)
        XCTAssertTrue(VatTreatment.standard.notes(german: true).isEmpty)
    }

    func testAnInvoiceWithManyLinesBreaksAcrossPages() throws {
        // Uncommon but real — a year of licences on one invoice.
        let items = (1...60).map {
            LineItem(description: "Licence \($0)", amount: "£10.00", unitPrice: "£10.00")
        }
        let invoice = Invoice(
            branding: Branding(name: "T"), number: "INV-1",
            from: Party(name: "S", address: ["1"], taxID: "GB1"),
            to: Party(name: "B", address: ["2"]),
            items: items,
            totals: [("Subtotal", "£600.00")],
            total: [("Total due", "£720.00")],
            supplyDate: "1 Aug"
        )
        let document = try invoice.render()
        XCTAssertGreaterThan(document.pageCount(), 1)

        // The item table's heading must repeat, or page two is a column of
        // unlabelled numbers.
        let stream = String(decoding: document.render(), as: UTF8.self)
        XCTAssertGreaterThan(stream.components(separatedBy: "(Description) Tj").count - 1, 1)
    }

    func testACompleteInvoicePasses() {
        XCTAssertTrue(minimalInvoice().complianceWarnings().isEmpty)
    }

    func testCreditNoteMustCiteTheOriginalInvoice() {
        // You cannot amend an invoice — sequential numbering forbids it — so a
        // credit note that references nothing is unusable.
        XCTAssertTrue(
            minimalInvoice(kind: .creditNote).complianceWarnings()
                .contains { $0.contains("reference the invoice") }
        )
        XCTAssertTrue(minimalInvoice(kind: .creditNote, reference: "INV-1").complianceWarnings().isEmpty)
    }

    func testSelfBilledInvoiceDemandsTheSupplierVatNumber() {
        // HMRC requires both parties' numbers on a self-billed invoice —
        // the supplier's is what makes it their invoice.
        let base = minimalInvoice(kind: .selfBilling)
        XCTAssertTrue(base.complianceWarnings().contains { $0.contains("supplier's VAT number") })
    }

    func testDebitNoteMustReferenceWhatItAdjusts() {
        XCTAssertTrue(
            minimalInvoice(kind: .debitNote).complianceWarnings()
                .contains { $0.contains("reference the document") }
        )
    }
}
