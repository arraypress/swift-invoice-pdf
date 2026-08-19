//
//  FacturXTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Countries
import PDFKit
import XCTest
@testable import InvoicePDF
import Money
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
            branding: Branding(name: "Meridian Studio Ltd"),
            number: number,
            from: Party(name: "Meridian Studio Ltd",
                        address: ["71 Shelton Street", "London"], taxID: supplierVAT,
                        country: Country("GB")),
            to: Party(name: "Klangwerk GmbH",
                      address: ["Oranienburger Str. 87", "Berlin"], taxID: customerVAT,
                      country: Country("DE")),
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

    func testARateWithThreeDecimalsSurvives() throws {
        // 8.875 went through Money in a two-decimal pseudo-currency and came
        // out 8.88 — a rate silently altered on a tax document. A rate is not
        // an amount; it is written exactly.
        let xml = try text(try invoice().facturX(details(rate: 8.875)))
        XCTAssertTrue(xml.contains("<ram:RateApplicablePercent>8.875</ram:RateApplicablePercent>"), xml)
    }

    func testAnOrdinaryRateKeepsItsTwoPlaces() throws {
        // What the validators saw: 20 written 20.00.
        let xml = try text(try invoice().facturX(details()))
        XCTAssertTrue(xml.contains("<ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>"), xml)
    }

    func testNoBuyerReferenceMeansNoElement() throws {
        // BT-10 is optional; an empty element is the one form that satisfies
        // neither reading, and some validators flag "present but empty"
        // louder than absent.
        let bare = FacturX(currency: "GBP", issued: issued,
                           totals: .init(net: 749, tax: 149.80, gross: 898.80), taxRate: 20)
        let xml = try text(try invoice().facturX(bare))

        XCTAssertFalse(xml.contains("<ram:BuyerReference"), xml)
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse(), "omitting it broke the XML")

        let referenced = try text(try invoice().facturX(details()))
        XCTAssertTrue(referenced.contains("<ram:BuyerReference>PO-4471</ram:BuyerReference>"))
    }

    func testMarkupInANameIsEscaped() throws {
        var party = invoice()
        let hostile = Invoice(
            branding: Branding(name: "x"), number: "INV-1",
            from: Party(name: "Smith & Sons <Ltd>", address: ["1 Road"], taxID: "GB1",
                        country: Country("GB")),
            to: Party(name: "Buyer", address: ["2 Road"], country: Country("DE")),
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
        // `Data`, not `Alternative`: the specification keys this to the
        // profile, and Minimum and Basic WL — the two this library writes —
        // carry only part of the invoice, so their XML is not an alternative
        // representation of the page. `Alternative` belongs to Basic and up,
        // and a Factur-X validator checks which is which.
        XCTAssertTrue(raw.contains("/AFRelationship /Data"))
        XCTAssertFalse(raw.contains("/AFRelationship /Alternative"))
        XCTAssertTrue(raw.contains("GTS_PDFA1"))
    }

    func testANameTheFamilyCannotDrawRefusesToClaimConformance() throws {
        // Arial has no CJK. The name falls back to the reader's Helvetica —
        // a font the file does not carry — and the page shows question marks.
        // Either alone disqualifies the PDF/A claim, so the render is refused
        // rather than shipped: a file that fails the standard it claims is
        // rejected days later, against your name.
        var latin = FontFamily(name: "Arial")
        latin.add(try EmbeddedFont.load(
            URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")), weight: .regular)

        let overseas = Invoice(
            branding: Branding(name: "Meridian Studio Ltd"),
            number: "INV-2026-0043",
            from: Party(name: "Meridian Studio Ltd", address: ["71 Shelton Street", "London"],
                        taxID: "GB123456789", country: Country("GB")),
            to: Party(name: "北京商贸有限公司", address: ["1 Jianguomen Ave", "Beijing"],
                      country: Country("CN")),
            items: [LineItem(description: "Licence", amount: "£749.00")],
            totals: [("Subtotal", "£749.00")],
            supplyDate: "31 July 2026"
        )

        XCTAssertThrowsError(
            try overseas.facturXDocument(details(), in: latin, creationDate: issued)
        ) { error in
            guard case Invoice.FacturXError.notConforming(let problems) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertFalse(problems.isEmpty)
            XCTAssertTrue("\(error)".contains("PDF/A"), "\(error)")
        }
    }

    func testTheAttachmentIsNamedExactlyWhatReadersLookFor() throws {
        let data = try invoice().facturXDocument(details(), in: try family(), creationDate: issued)
        let raw = try XCTUnwrap(String(data: data, encoding: .isoLatin1))

        // Factur-X readers look for this filename, exactly.
        XCTAssertTrue(raw.contains("/F (factur-x.xml)"), "the filename is not the one readers open")
    }

    func testTheFacturXMetadataTravelsInThePacket() throws {
        // PDF/A forbids XMP properties the file does not declare a schema
        // for, and a Factur-X validator reads the conformance level from the
        // packet rather than from the XML — without both halves the file
        // fails as Factur-X however sound its PDF/A is. The packet is
        // written uncompressed, so the bytes are searchable as text.
        let minimum = try invoice().facturXDocument(details(), in: try family(),
                                                    creationDate: issued)
        let raw = try XCTUnwrap(String(data: minimum, encoding: .isoLatin1))

        XCTAssertTrue(raw.contains("<pdfaSchema:prefix>fx</pdfaSchema:prefix>"),
                      "no extension schema declaring fx:")
        XCTAssertTrue(raw.contains("<fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>"))
        XCTAssertTrue(raw.contains("<fx:DocumentType>INVOICE</fx:DocumentType>"))
        XCTAssertTrue(raw.contains("<fx:ConformanceLevel>MINIMUM</fx:ConformanceLevel>"),
                      "the conformance level did not reach the packet")

        let basic = try invoice().facturXDocument(details(profile: .basicWithoutLines),
                                                  in: try family(), creationDate: issued)
        let basicRaw = try XCTUnwrap(String(data: basic, encoding: .isoLatin1))
        XCTAssertTrue(basicRaw.contains("<fx:ConformanceLevel>BASIC WL</fx:ConformanceLevel>"),
                      "the level must follow the profile")
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

// MARK: - Currencies that are not the euro

extension FacturXTests {

    private func amounts(_ currency: String, net: Decimal, tax: Decimal, gross: Decimal) throws -> String {
        try text(try invoice().facturX(FacturX(
            currency: currency, issued: issued,
            totals: .init(net: net, tax: tax, gross: gross)
        )))
    }

    func testTheYenHasNoMinorUnit() throws {
        // ¥1000 is written 1000. Writing 1000.00 says its author did not know
        // that, and some validators say so louder.
        let xml = try amounts("JPY", net: 1000, tax: 0, gross: 1000)

        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>1000</ram:GrandTotalAmount>"), xml)
        XCTAssertFalse(xml.contains("1000.00"), "the yen was given decimals it does not have")
    }

    func testTheDinarCannotBeAnEInvoiceAtAll() throws {
        // Found by running the official validator, and not what this file
        // asserted before: EN 16931 caps every document-level amount at two
        // decimals — BR-DEC-09 through BR-DEC-20 — whatever minor unit the
        // currency has. The dinar has three, so the standard has nowhere to
        // put a fils.
        //
        // Refused rather than rounded. Rounding would make the XML disagree
        // with the page, invisibly, until somebody reconciled the two.
        XCTAssertThrowsError(try amounts("KWD", net: 1.234, tax: 0, gross: 1.234)) {
            let said = "\($0)"
            XCTAssertTrue(said.contains("KWD"), said)
            XCTAssertTrue(said.contains("BR-DEC"), said)
        }
    }

    func testTheOrdinaryCaseIsUnchanged() throws {
        let xml = try amounts("EUR", net: 749, tax: 149.80, gross: 898.80)
        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>898.80</ram:GrandTotalAmount>"), xml)
    }

    func testTheCurrencysOwnPrecisionIsUsed() {
        // The table lives in swift-money now, and is cross-checked against
        // ICU there. What matters here is that the XML uses it.
        XCTAssertEqual(Currency("JPY").decimals, 0)
        XCTAssertEqual(Currency("KWD").decimals, 3)
        XCTAssertEqual(Currency("GBP").decimals, 2)
    }

    func testAYenOfRoundingIsAllowedAndTenAreNot() {
        // A penny of tolerance would be a hundred times too loose here.
        XCTAssertEqual(
            FacturX.Totals(net: 1000, tax: 100, gross: 1101).disagreements(currency: "JPY"), []
        )
        XCTAssertFalse(
            FacturX.Totals(net: 1000, tax: 100, gross: 1110).disagreements(currency: "JPY").isEmpty
        )
    }

    func testAFilsOfRoundingIsAllowedOnADinar() {
        // And a penny of tolerance would be ten times too loose.
        XCTAssertEqual(
            FacturX.Totals(net: 1.000, tax: 0.200, gross: 1.201).disagreements(currency: "KWD"), []
        )
        XCTAssertFalse(
            FacturX.Totals(net: 1.000, tax: 0.200, gross: 1.210).disagreements(currency: "KWD").isEmpty
        )
    }

    func testTheMessageIsWrittenInTheCurrencysOwnPrecision() {
        let found = FacturX.Totals(net: 1000, tax: 0, gross: 900).disagreements(currency: "JPY")
        XCTAssertTrue(try! XCTUnwrap(found.first).contains("JPY 1000"), found.joined())
        XCTAssertFalse(try! XCTUnwrap(found.first).contains("1000.00"), found.joined())
    }
}

extension FacturXTests {


}

extension FacturXTests {

    func testTaxComputedFromARateIsRoundedRatherThanRefused() throws {
        // 20% of 1234.56 is 246.912, and every accounting system on earth
        // writes 246.91. Refusing it — which an earlier version of this did —
        // is refusing ordinary arithmetic.
        let xml = try text(try invoice().facturX(FacturX(
            currency: "GBP", issued: issued,
            totals: .init(net: 1234.56, tax: 246.912, gross: 1481.47), taxRate: 20
        )))

        XCTAssertTrue(xml.contains("<ram:CalculatedAmount>246.91</ram:CalculatedAmount>"), xml)
    }

    func testTheTotalsAreCheckedAsTheyArePrinted() throws {
        // Checking the unrounded figures would report a disagreement nobody
        // can see: 1234.56 + 246.912 is 1481.472, and the page says 1481.47.
        XCTAssertEqual(
            FacturX.Totals(net: 1234.56, tax: 246.912, gross: 1481.47)
                .disagreements(currency: "GBP"),
            []
        )
    }

    func testHalfAYenIsRoundedTheWayTheDocumentPrintsIt() throws {
        // A tax of 10% on ¥10,005 is ¥1000.5, which is a real figure that a
        // real invoice rounds. It is written as a whole number of yen.
        let xml = try text(try invoice().facturX(FacturX(
            currency: "JPY", issued: issued,
            totals: .init(net: 10005, tax: 1000.5, gross: 11006)
        )))

        XCTAssertTrue(xml.contains("<ram:CalculatedAmount>1001</ram:CalculatedAmount>"), xml)
        XCTAssertFalse(xml.contains("1000.5"), "the yen was written with a decimal")
    }
}
