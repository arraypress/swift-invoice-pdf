//
//  TextSurvivalTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Nothing a customer typed is cut or lost. A description too long for its
//  column wraps; a note too long for the page carries on over it; a row
//  taller than a page flows under the repeated header. Each is asserted by
//  reading the rendered page back, as the recipient would, because a cut
//  description and a short one look exactly alike.
//

import Foundation
import PDFKit
import XCTest
import TextPDF
@testable import InvoicePDF

final class TextSurvivalTests: XCTestCase {

    private let seller = Party(name: "Lachlan Weaving Ltd", address: ["14 Thistle Wynd", "Dunfermline KY12 7QP"],
                               taxID: "GB123456789")
    private let buyer = Party(name: "Hafenkontor GmbH", address: ["Speicherstadt 9", "20457 Hamburg"],
                              taxID: "DE811567890")

    /// Distinct tokens, none a prefix of another, so finding one proves it.
    private func words(_ count: Int, _ stem: String = "w") -> [String] {
        (1...count).map { String(format: "\(stem)%04dx", $0) }
    }

    private func invoice(items: [LineItem], notes: String = "",
                         paymentCode: PaymentCode? = nil) -> Invoice {
        Invoice(
            branding: Branding(name: "Lachlan"), number: "INV-1",
            from: seller, to: buyer, items: items,
            totals: [("Subtotal", "£1,200.00")], total: [("Total due", "£1,200.00")],
            notes: notes, supplyDate: "28 July 2026", paymentCode: paymentCode
        )
    }

    /// Every page, whitespace squeezed out: extraction inserts its own.
    private func pages(_ document: TextPDF.Document) throws -> [String] {
        let pdf = try XCTUnwrap(PDFDocument(data: document.render()))
        return (0..<pdf.pageCount).map { (pdf.page(at: $0)?.string ?? "").filter { !$0.isWhitespace } }
    }

    // MARK: Item descriptions

    func testALongDescriptionWrapsAndKeepsEveryWord() throws {
        let description = words(40).joined(separator: " ")
        let item = LineItem(description: description, amount: "£1,200.00", quantity: "3",
                            unitPrice: "£400.00", note: words(30, "n").joined(separator: " "))
        let built = invoice(items: [item])
        let document = try built.render()
        let all = try pages(document).joined()

        for word in words(40) + words(30, "n") {
            XCTAssertTrue(all.contains(word), "lost \(word)")
        }
        XCTAssertFalse(all.contains("..."), "something was shortened")
        XCTAssertEqual(built.complianceWarnings(verifying: document).filter { $0.contains("item") }, [])
    }

    /// A wrapped row grows: the next row starts underneath it, not on top.
    func testAWrappedRowPushesTheNextOneDown() throws {
        let short = try invoice(items: [LineItem(description: "One", amount: "£1.00"),
                                        LineItem(description: "Two", amount: "£1.00")]).render()
        let long = try invoice(items: [LineItem(description: words(40).joined(separator: " "), amount: "£1.00"),
                                       LineItem(description: "Two", amount: "£1.00")]).render()
        XCTAssertLessThan(long.cursor(), short.cursor())
    }

    /// A description longer than a whole page cannot be kept on one. It flows
    /// on under the repeated header rather than running off the foot.
    func testARowTallerThanAPageFlowsOnto() throws {
        let tokens = words(1400)
        let built = invoice(items: [LineItem(description: tokens.joined(separator: " "), amount: "£1.00"),
                                    LineItem(description: "afterwards", amount: "£2.00")])
        let read = try pages(try built.render())

        XCTAssertGreaterThan(read.count, 1)
        let all = read.joined()
        for word in tokens { XCTAssertTrue(all.contains(word), "lost \(word)") }
        XCTAssertTrue(all.contains("afterwards"))
        XCTAssertTrue(read[1].contains("Description"), "the header repeats over the break")
    }

    func testManyItemsAcrossPagesAreAllThere() throws {
        let tokens = words(160, "item")
        let built = invoice(items: tokens.map { LineItem(description: $0, amount: "£1.00") })
        let read = try pages(try built.render())

        XCTAssertGreaterThan(read.count, 2)
        let all = read.joined()
        for word in tokens { XCTAssertTrue(all.contains(word), "lost \(word)") }
    }

    // MARK: Notes

    func testLongPaymentNotesCarryOnOverThePage() throws {
        let tokens = words(900, "p")
        let built = invoice(items: [LineItem(description: "Tweed", amount: "£1.00")],
                            notes: tokens.joined(separator: " "))
        let read = try pages(try built.render())

        XCTAssertGreaterThan(read.count, 1)
        let all = read.joined()
        for word in tokens { XCTAssertTrue(all.contains(word), "lost \(word)") }
    }

    /// With a payment code beside them, overflowing notes still all arrive,
    /// and the code is drawn on the page the notes start on.
    func testLongNotesBesideAPaymentCodeAllArrive() throws {
        let tokens = words(900, "q")
        let built = invoice(items: [LineItem(description: "Tweed", amount: "£1.00")],
                            notes: tokens.joined(separator: " "),
                            paymentCode: PaymentCode("https://pay.example/INV-1"))
        let document = try built.render()
        let read = try pages(document)

        let all = read.joined()
        for word in tokens { XCTAssertTrue(all.contains(word), "lost \(word)") }
        XCTAssertTrue(read[0].contains("Scantopay"), "the code belongs beside the start of the notes")
    }

    func testLongStatementNotesCarryOnOverThePage() throws {
        let tokens = words(900, "s")
        let statement = Statement(
            branding: Branding(name: "Lachlan"), account: buyer, period: "July 2026",
            transactions: [Transaction(date: "1 Jul", description: "Opening", balance: "£0.00")],
            notes: tokens.joined(separator: " "))
        let read = try pages(try statement.render())

        let all = read.joined()
        for word in tokens { XCTAssertTrue(all.contains(word), "lost \(word)") }
    }

    // MARK: Checking the drawn page

    /// A description that did not reach the page — cut, or never drawn — is
    /// reported, whatever the data says.
    func testAnItemMissingFromThePageIsReported() {
        let item = LineItem(description: "Harris tweed, 40 m, herringbone", amount: "£1.00",
                            note: "Woven in Stornoway")
        let blank = TextPDF.Document()
        blank.textAt("Harris tweed, 40 m, herr...", x: 50, y: 400, size: 9)

        let warnings = invoice(items: [item]).complianceWarnings(verifying: blank)
        XCTAssertTrue(warnings.contains(
            "The item description \"Harris tweed, 40 m, herringbone\" did not reach the page in full."))
        XCTAssertTrue(warnings.contains(
            "The item note \"Woven in Stornoway\" did not reach the page in full."))
    }
}
