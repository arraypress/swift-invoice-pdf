//
//  TemplateReaderTests.swift
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

final class TemplateReaderTests: XCTestCase {

    private func open(_ pdf: Data, file: StaticString = #filePath, line: UInt = #line) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: pdf), "PDFKit refused the file", file: file, line: line)
    }


    // MARK: Templates

    func testARenderedInvoiceOpensAndReads() throws {
        let invoice = Invoice(
            branding: Branding(name: "Meridian Studio Ltd", address: ["71-75 Shelton Street", "London WC2H 9JQ"]),
            number: "INV-2026-0042",
            from: Party(name: "Meridian Studio Ltd", address: ["71-75 Shelton Street"], taxID: "GB123456789"),
            to: Party(name: "Acme Recordings Ltd", address: ["Studio 4, 118 Brick Lane"]),
            items: [LineItem(description: "Drum Kit Vol. 2", amount: "£149.00", unitPrice: "£149.00")],
            totals: [(label: "Subtotal", value: "£149.00")],
            total: [(label: "Total due", value: "£178.80")],
            supplyDate: "31 July 2026"
        )

        let opened = try open(invoice.render().render())
        let read = try XCTUnwrap(opened.string)
        for expected in ["INVOICE", "INV-2026-0042", "Acme Recordings Ltd", "Drum Kit Vol. 2", "£178.80"] {
            XCTAssertTrue(read.contains(expected), "\"\(expected)\" missing from: \(read)")
        }
    }
}
