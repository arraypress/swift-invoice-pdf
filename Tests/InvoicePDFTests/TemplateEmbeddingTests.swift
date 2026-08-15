//
//  TemplateEmbeddingTests.swift
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

final class TemplateEmbeddingTests: XCTestCase {

    private let unicodeFont = URL(fileURLWithPath: "/Library/Fonts/Arial Unicode.ttf")

    private func loadUnicodeFont() throws -> EmbeddedFont {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: unicodeFont.path),
                          "Arial Unicode is not installed")
        return try EmbeddedFont.load(unicodeFont)
    }


    func testTemplatesTakeTheFontBeforeDrawing() throws {
        let font = try loadUnicodeFont()
        let invoice = Invoice(
            branding: Branding(name: "ArrayPress"),
            number: "INV-1",
            from: Party(name: "ArrayPress Ltd", taxID: "GB123"),
            to: Party(name: "ООО Ромашка"),
            items: [LineItem(description: "Лицензия", amount: "€100,00")],
            total: [(label: "Total", value: "€100,00")]
        )

        // Attaching a font after the fact cannot work — the text is already in
        // the content stream by then — so the template has to be given it.
        let without = invoice.render()
        XCTAssertFalse(without.substitutions.isEmpty)

        let with = invoice.render(embedding: font)
        XCTAssertTrue(with.substitutions.isEmpty, "\(with.substitutions)")
        XCTAssertTrue(String(decoding: with.render(), as: UTF8.self).contains("/FontFile2"))
    }
}
