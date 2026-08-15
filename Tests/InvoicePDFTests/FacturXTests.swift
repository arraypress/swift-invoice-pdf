//
//  FacturXTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import PDFKit
import XCTest
@testable import InvoicePDF
import TextPDF

final class FacturXTests: XCTestCase {

    private let issued = Date(timeIntervalSince1970: 1_785_000_000)   // 25 July 2026
    private let payable = Date(timeIntervalSince1970: 1_787_600_000)  // 24 August 2026

    private func invoice(
        kind: DocumentKind = .invoice,
        supplierVAT: String = "GB123456789",
        customerVAT: String = "DE811567890",
        vat: VatTreatment = .standard,
        number: String = "INV-2026-0042"
    ) -> Invoice {
        Invoice(
            kind: kind,
            branding: Branding(name: "SwiftInvoices Ltd"),
            number: number,
            from: Party(name: "SwiftInvoices Ltd",
                        address: ["71 Shelton Street", "London", "GB"], taxID: supplierVAT),
            to: Party(name: "Klangwerk GmbH",
                      address: ["Oranienburger Str. 87", "Berlin", "DE"], taxID: customerVAT),
            items: [LineItem(description: "Licence", amount: "£749.00")],
            totals: [("Subtotal", "£749.00")],
            vat: vat,
            supplyDate: "31 July 2026",
            reference: "PO-4471"
        )
    }

    private func details(
        profile: FacturX.Profile = .minimum,
        currency: String = "GBP",
        net: Decimal = 749, tax: Decimal = 149.80, gross: Decimal = 898.80,
        rate: Decimal = 20
    ) -> FacturX {
        FacturX(
            profile: profile, currency: currency, issued: issued, due: payable,
            totals: .init(net: net, tax: tax, gross: gross), taxRate: rate,
            buyerReference: "PO-4471"
        )
    }

    private func text(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    // MARK: The XML

    func testItIsWellFormed() throws {
        let xml = try invoice().facturX(details())
        XCTAssertTrue(XMLParser(data: xml).parse(), "the XML does not parse")
    }

    func testItCarriesWhatTheStandardAsksFor() throws {
        let xml = try text(try invoice().facturX(details()))

        XCTAssertTrue(xml.contains("<ram:ID>INV-2026-0042</ram:ID>"))
        XCTAssertTrue(xml.contains("<ram:TypeCode>380</ram:TypeCode>"))
        XCTAssertTrue(xml.contains("urn:factur-x.eu:1p0:minimum"))
        XCTAssertTrue(xml.contains("<ram:InvoiceCurrencyCode>GBP</ram:InvoiceCurrencyCode>"))
        XCTAssertTrue(xml.contains("schemeID=\"VA\">GB123456789"))
        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>898.80</ram:GrandTotalAmount>"))
        XCTAssertTrue(xml.contains("<ram:DuePayableAmount>898.80</ram:DuePayableAmount>"))
    }

    func testDatesAreMachineReadable() throws {
        // "31 July 2026" is for a person; a system reading it has to guess a
        // locale to know which number is the month.
        let xml = try text(try invoice().facturX(details()))

        XCTAssertTrue(xml.contains("format=\"102\">20260725</udt:DateTimeString>"), xml)
        XCTAssertTrue(xml.contains("format=\"102\">20260824</udt:DateTimeString>"))
    }

    func testAmountsAreDecimalWhateverTheLocale() throws {
        // The page may say "€1.234,56"; the schema wants 1234.56, always.
        let xml = try text(try invoice().facturX(
            details(net: 1234.56, tax: 246.912, gross: 1481.47)
        ))

        XCTAssertTrue(xml.contains("<ram:LineTotalAmount>1234.56</ram:LineTotalAmount>"), xml)
        XCTAssertTrue(xml.contains("<ram:CalculatedAmount>246.91</ram:CalculatedAmount>"),
                      "the tax was not rounded to the currency's places")
        XCTAssertFalse(xml.contains("1,234"), "a thousands separator reached the XML")
    }

    func testTheProfileIsDeclared() throws {
        let basic = try text(try invoice().facturX(details(profile: .basicWithoutLines)))
        XCTAssertTrue(basic.contains("urn:factur-x.eu:1p0:basicwl"))
    }

    func testMarkupInANameIsEscaped() throws {
        var party = invoice()
        let hostile = Invoice(
            branding: Branding(name: "x"), number: "INV-1",
            from: Party(name: "Smith & Sons <Ltd>", address: ["1 Road", "GB"], taxID: "GB1"),
            to: Party(name: "Buyer", address: ["2 Road", "DE"]),
            items: [], totals: []
        )
        party = hostile

        let xml = try text(try party.facturX(details()))
        XCTAssertTrue(xml.contains("Smith &amp; Sons &lt;Ltd&gt;"), xml)
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse(), "escaping did not save it")
    }

    // MARK: Kinds

    func testEachKindCarriesItsOwnCode() throws {
        let codes: [DocumentKind: String] = [
            .invoice: "380", .creditNote: "381", .debitNote: "383",
            .proforma: "325", .selfBilling: "389",
        ]

        for (kind, code) in codes {
            let xml = try text(try invoice(kind: kind).facturX(details()))
            XCTAssertTrue(xml.contains("<ram:TypeCode>\(code)</ram:TypeCode>"), kind.rawValue)
        }
    }

    func testWhatIsNotAnInvoiceIsRefused() throws {
        // Giving a delivery note an invoice code to make the file generate
        // would put a document into somebody's ledger as a bill.
        for kind in [DocumentKind.quote, .receipt, .reminder, .remittance,
                     .deliveryNote, .purchaseOrder, .orderConfirmation] {
            XCTAssertThrowsError(try invoice(kind: kind).facturX(details()), kind.rawValue) { error in
                XCTAssertEqual(error as? Invoice.FacturXError, .notAnInvoice(kind))
            }
        }
    }

    // MARK: Refusing

    func testAnInvoiceWithoutASupplierVATNumberIsRefused() throws {
        XCTAssertThrowsError(try invoice(supplierVAT: "").facturX(details())) { error in
            XCTAssertTrue("\(error)".contains("VAT"), "\(error)")
        }
    }

    func testReverseChargeNeedsTheCustomersNumber() throws {
        XCTAssertThrowsError(
            try invoice(customerVAT: "", vat: .reverseCharge).facturX(details())
        ) { error in
            XCTAssertTrue("\(error)".contains("customer's VAT number"), "\(error)")
        }
    }

    func testAnInvoiceWithoutANumberIsRefused() throws {
        XCTAssertThrowsError(try invoice(number: " ").facturX(details()))
    }

    func testANonsenseCurrencyIsRefused() throws {
        XCTAssertThrowsError(try invoice().facturX(details(currency: "pounds"))) { error in
            XCTAssertTrue("\(error)".contains("ISO 4217"), "\(error)")
        }
    }

    func testTheRefusalSaysWhatIsWrong() throws {
        do {
            _ = try invoice(supplierVAT: "").facturX(details(currency: "X"))
            XCTFail("it should have refused")
        } catch let error as Invoice.FacturXError {
            // Everything wrong at once, not the first thing found — otherwise
            // fixing an invoice is a conversation.
            XCTAssertTrue("\(error)".contains("VAT"))
            XCTAssertTrue("\(error)".contains("ISO 4217"))
        }
    }

    // MARK: Tax categories

    func testTheTreatmentBecomesACategoryCode() throws {
        let expected: [VatTreatment: String] = [
            .standard: "S", .reverseCharge: "AE", .intraCommunitySupply: "K",
            .export: "G", .smallBusiness: "E", .exempt: "E",
        ]

        for (treatment, code) in expected {
            let xml = try text(try invoice(vat: treatment)
                .facturX(details(tax: 0, gross: 749, rate: 0)))
            XCTAssertTrue(xml.contains("<ram:CategoryCode>\(code)</ram:CategoryCode>"),
                          treatment.rawValue)
        }
    }

    func testZeroTaxCarriesItsReason() throws {
        // A system that sees "0" with no reason files it as a mistake.
        let xml = try text(try invoice(vat: .reverseCharge)
            .facturX(details(tax: 0, gross: 749, rate: 0)))
        XCTAssertTrue(xml.contains("<ram:ExemptionReason>Reverse charge</ram:ExemptionReason>"), xml)
    }

    // MARK: The whole file

    private func family() throws -> FontFamily {
        let arial = URL(fileURLWithPath: "/Library/Fonts/Arial Unicode.ttf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: arial.path), "no face to embed")

        var family = FontFamily(name: "Arial Unicode")
        family.add(try EmbeddedFont.load(arial), weight: .regular)
        return family
    }

    private func attachment(_ data: Data, named wanted: String) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog
        else { return nil }

        var names: CGPDFDictionaryRef?
        var embedded: CGPDFDictionaryRef?
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names,
              CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &embedded), let embedded,
              CGPDFDictionaryGetArray(embedded, "Names", &array), let array
        else { return nil }

        var index = 0
        while index + 1 < CGPDFArrayGetCount(array) {
            var nameRef: CGPDFStringRef?
            var spec: CGPDFDictionaryRef?
            CGPDFArrayGetString(array, index, &nameRef)
            CGPDFArrayGetDictionary(array, index + 1, &spec)

            if let nameRef, let spec, let cf = CGPDFStringCopyTextString(nameRef),
               (cf as String) == wanted {
                var ef: CGPDFDictionaryRef?
                var stream: CGPDFStreamRef?
                CGPDFDictionaryGetDictionary(spec, "EF", &ef)
                if let ef, CGPDFDictionaryGetStream(ef, "F", &stream), let stream {
                    var format = CGPDFDataFormat.raw
                    return CGPDFStreamCopyData(stream, &format) as Data?
                }
            }
            index += 2
        }
        return nil
    }

    func testAnEInvoiceIsOneFileWithBothHalves() throws {
        let invoice = invoice()
        let data = try invoice.facturXDocument(details(), in: try family(),
                                               creationDate: issued)

        // The half a person reads.
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(try XCTUnwrap(document.string).contains("INV-2026-0042"))

        // The half a ledger reads, byte for byte.
        let carried = try XCTUnwrap(attachment(data, named: "factur-x.xml"),
                                    "the XML did not travel with the document")
        XCTAssertEqual(carried, try invoice.facturX(details()))
        XCTAssertTrue(XMLParser(data: carried).parse())

        // And it claims the standard honestly.
        let raw = try XCTUnwrap(String(data: data, encoding: .isoLatin1))
        XCTAssertTrue(raw.hasPrefix("%PDF-1.7"))
        XCTAssertTrue(raw.contains("<pdfaid:part>3</pdfaid:part>"))
        XCTAssertTrue(raw.contains("/AFRelationship /Alternative"))
        XCTAssertTrue(raw.contains("GTS_PDFA1"))
    }

    func testTheAttachmentIsNamedExactlyWhatReadersLookFor() throws {
        let data = try invoice().facturXDocument(details(), in: try family(), creationDate: issued)
        let raw = try XCTUnwrap(String(data: data, encoding: .isoLatin1))

        // Factur-X readers look for this filename, exactly.
        XCTAssertTrue(raw.contains("/F (factur-x.xml)"), "the filename is not the one readers open")
    }

    func testTheSameInvoiceTwiceIsTheSameFile() throws {
        let invoice = invoice()
        let first = try invoice.facturXDocument(details(), in: try family(), creationDate: issued)
        let second = try invoice.facturXDocument(details(), in: try family(), creationDate: issued)

        XCTAssertEqual(first, second)
    }

    func testARefusedInvoiceProducesNoFileAtAll() throws {
        // Rather than a PDF with no XML in it, which looks fine until a
        // buyer's system rejects it days later and against your name.
        XCTAssertThrowsError(
            try invoice(supplierVAT: "").facturXDocument(details(), in: try family())
        )
    }
}

// MARK: - Figures that do not agree

extension FacturXTests {

    func testATotalThatDoesNotAddUpIsCaught() throws {
        // The most embarrassing thing an invoice can carry, and the one a
        // customer notices first.
        let wrong = FacturX.Totals(net: 749, tax: 149.80, gross: 890)
        let found = wrong.disagreements(currency: "GBP")

        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(try XCTUnwrap(found.first).contains("898.80"), found.joined())
        XCTAssertTrue(try XCTUnwrap(found.first).contains("890.00"), found.joined())
    }

    func testFiguresThatAgreeSayNothing() {
        XCTAssertEqual(FacturX.Totals(net: 749, tax: 149.80, gross: 898.80).disagreements(), [])
    }

    func testAPennyOfRoundingIsAllowed() {
        // A rate applied per line lands there legitimately.
        XCTAssertEqual(FacturX.Totals(net: 100, tax: 19.99, gross: 120).disagreements(), [])
        XCTAssertFalse(FacturX.Totals(net: 100, tax: 19, gross: 120).disagreements().isEmpty)
    }

    func testPayingMoreThanTheInvoiceIsForIsCaught() {
        let found = FacturX.Totals(net: 100, tax: 20, gross: 120, due: 200).disagreements()
        XCTAssertTrue(found.contains { $0.contains("More is payable") }, found.joined())
    }

    func testANegativeAmountIsCaught() {
        // A refund is a credit note, not a minus sign.
        let found = FacturX.Totals(net: -100, tax: -20, gross: -120).disagreements()
        XCTAssertTrue(found.contains { $0.contains("negative") }, found.joined())
    }

    func testPayingLessIsFine() {
        // A part payment against an open invoice.
        XCTAssertEqual(FacturX.Totals(net: 100, tax: 20, gross: 120, due: 60).disagreements(), [])
    }

    func testTheXMLRefusesFiguresThatDisagree() throws {
        XCTAssertThrowsError(
            try invoice().facturX(details(net: 749, tax: 149.80, gross: 890))
        ) { error in
            XCTAssertTrue("\(error)".contains("does not add up"), "\(error)")
        }
    }

    func testTheXMLIsHappyWhenTheyAgree() throws {
        XCTAssertNoThrow(try invoice().facturX(details()))
    }
}
