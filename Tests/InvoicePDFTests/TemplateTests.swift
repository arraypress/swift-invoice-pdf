//
//  TemplateTests.swift
//  TextPDF
//
//  Created by David Sherlock on 2026.
//

import PDFKit
import XCTest
@testable import InvoicePDF
import TextPDF

/// The documents added alongside the invoice and the statement.
///
/// These check the things that make each document the document it is — a
/// packing list without prices, a customs line that keeps its country of
/// origin — rather than that a PDF came out at all.
final class TemplateTests: XCTestCase {

    private let brand = Branding(name: "ArrayPress", accent: "#0f766e")

    /// The file as text.
    ///
    /// Decoded as Latin-1, which is what the writer encodes: `£` is one byte
    /// there and not valid UTF-8 on its own, so decoding it as UTF-8 replaces
    /// it and nothing containing a currency symbol can be found.
    private func text(of document: Document) -> String {
        String(data: document.render(), encoding: .isoLatin1) ?? ""
    }

    // MARK: Wrapped blocks

    func testLongTextWrapsRatherThanRunningOffThePage() throws {
        let pdf = Document(size: .a4, margin: 48)
        let sentence = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6)

        let height = pdf.block(sentence, x: pdf.left(), width: 200, size: 9, leading: 12)

        // A single line would be 12 points; this has to have wrapped.
        XCTAssertGreaterThan(height, 12 * 5)
        XCTAssertEqual(height, pdf.blockHeight(sentence, size: 9, width: 200, leading: 12), accuracy: 0.01)
    }

    func testBlockRespectsExplicitLineBreaks() throws {
        let pdf = Document(size: .a4, margin: 48)
        let two = pdf.blockHeight("one\ntwo", size: 9, width: 400, leading: 12)
        let one = pdf.blockHeight("one", size: 9, width: 400, leading: 12)
        XCTAssertEqual(two, one * 2, accuracy: 0.01)
    }

    func testBlockAdvancesTheCursorByWhatItDrew() throws {
        let pdf = Document(size: .a4, margin: 48)
        let before = pdf.cursor()
        let height = pdf.block("A short line", x: pdf.left(), width: 400, size: 9, leading: 12)
        XCTAssertEqual(pdf.cursor(), before - height, accuracy: 0.01)
    }

    // MARK: Page flow

    func testGrowingAnInvoiceNeverHandsAPageBack() throws {
        // The regression this guards: when the VAT breakdown table broke to a
        // new page, the cursor was clamped back to where the *old* page
        // stopped — dragging it to the bottom of the fresh page, so the
        // totals and notes arrived a page late below most of a page of
        // nothing. Content only ever moves down, so adding a line item can
        // add a page but can never remove one; the bug showed up as exactly
        // that dip, at the row counts where the breakdown straddled a break.
        let wire = "Payment within 30 days by bank transfer to the account below. "
            + "Please quote the invoice number on the transfer, or the payment "
            + "cannot be matched and will sit unallocated until somebody writes "
            + "to ask about it, which helps neither of us. "
            + "Account: ArrayPress Ltd, 04-00-04 12345678."

        var previous = 0
        for count in 1...60 {
            let invoice = Invoice(
                branding: brand,
                number: "INV-\(count)",
                from: Party(name: "ArrayPress Ltd", address: ["71 Shelton Street"], taxID: "GB1"),
                to: Party(name: "Kestrel GmbH", address: ["Frankfurt"]),
                items: (1...count).map { LineItem(description: "Line \($0)", amount: "£10.00") },
                totals: [("Subtotal", "£\(count * 10).00")],
                total: [("Total due", "£\(count * 12).00")],
                notes: wire,
                vatLines: (1...5).map { VatLine(rate: "\($0)%", net: "£10.00", vat: "£0.50") },
                supplyDate: "1 Aug 2026"
            )

            let pages = try invoice.render().pageCount()
            XCTAssertGreaterThanOrEqual(pages, previous,
                                        "page count fell from \(previous) at \(count) line items")
            previous = pages
        }
    }

    // MARK: Tables

    func testTotalRowIsDrawnWithTheSameColumns() throws {
        let pdf = Document(size: .a4, margin: 48)
        let table = Table(headers: ["Account", "Current", "Total"])
        table.widths([0.5, 0.25, 0.25]).align([1: .right, 2: .right])
        table.row(["Northwind", "£100.00", "£100.00"])
        table.total(["Total", "£100.00", "£100.00"])
        table.draw(pdf, size: 9)

        let rendered = text(of: pdf)
        XCTAssertTrue(rendered.contains("(Total) Tj"))
        // Two occurrences of the figure: the row and the total beneath it.
        XCTAssertEqual(rendered.components(separatedBy: "(\u{A3}100.00) Tj").count - 1, 4)
    }

    // MARK: Timesheet

    func testTimesheetDropsMoneyColumnsWhenNothingIsCharged() throws {
        let internalSheet = Timesheet(
            branding: brand,
            worker: Party(name: "Daniel Okafor"),
            period: "July 2026",
            entries: [TimeEntry(date: "02 Jul", description: "Library maintenance", hours: "4.0", nonBillable: true)]
        )
        let rendered = text(of: try internalSheet.render())

        // Empty rate and amount columns on an internal sheet invite someone to
        // fill them in, so they are not drawn at all.
        XCTAssertFalse(rendered.contains("(Rate) Tj"))
        XCTAssertFalse(rendered.contains("(Amount) Tj"))
        XCTAssertTrue(rendered.contains("(Hours) Tj"))
    }

    func testTimesheetKeepsMoneyColumnsWhenTimeIsCharged() throws {
        let billed = Timesheet(
            branding: brand,
            worker: Party(name: "Daniel Okafor"),
            period: "July 2026",
            entries: [TimeEntry(date: "02 Jul", description: "Foley", hours: "6.5", rate: "£65.00", amount: "£422.50")]
        )
        let rendered = text(of: try billed.render())
        XCTAssertTrue(rendered.contains("(Rate) Tj"))
        XCTAssertTrue(rendered.contains("(Amount) Tj"))
    }

    func testNonBillableTimeIsMarkedInTheTextNotOnlyByColour() throws {
        let sheet = Timesheet(
            branding: brand,
            worker: Party(name: "Daniel Okafor"),
            period: "July 2026",
            entries: [TimeEntry(date: "02 Jul", description: "Library maintenance", hours: "4.0", nonBillable: true)]
        )
        // It has to survive a photocopy.
        XCTAssertTrue(text(of: try sheet.render()).contains("non-billable"))
    }

    // MARK: Royalty statement

    func testRoyaltyStatementDropsColumnsNobodyFilledIn() throws {
        let commission = RoyaltyStatement(
            branding: brand,
            payee: Party(name: "Mireille Fontaine"),
            period: "July 2026",
            lines: [RoyaltyLine(source: "Direct", title: "Tape Textures", net: "£143.00", earned: "£100.10")]
        )
        let rendered = text(of: try commission.render())
        XCTAssertFalse(rendered.contains("(Gross) Tj"))
        XCTAssertFalse(rendered.contains("(Distributor) Tj"))
        XCTAssertTrue(rendered.contains("(Earnings) Tj"))
    }

    func testRoyaltyStatementShowsTheWholeChainWhenGiven() throws {
        let full = RoyaltyStatement(
            branding: brand,
            payee: Party(name: "Mireille Fontaine"),
            period: "July 2026",
            lines: [
                RoyaltyLine(source: "Splice", title: "Analogue Drift", quantity: "1,284",
                            gross: "£3,210.00", distributorShare: "£1,605.00",
                            net: "£1,605.00", rate: "50%", earned: "£802.50"),
            ]
        )
        let rendered = text(of: try full.render())
        for column in ["Gross", "Distributor", "Net", "Share", "Earnings", "Units"] {
            XCTAssertTrue(rendered.contains("(\(column)) Tj"), "missing the \(column) column")
        }
    }

    func testCarriedForwardReasonIsPrintedOnTheDocument() throws {
        let unrecouped = RoyaltyStatement(
            branding: brand,
            payee: Party(name: "Mireille Fontaine"),
            period: "July 2026",
            lines: [RoyaltyLine(source: "Splice", title: "Analogue Drift", net: "£100.00", earned: "£50.00")],
            payable: [("Payable this period", "£0.00")],
            carriedForwardNote: "The advance is not yet recouped. An unrecouped balance is not a debt."
        )
        // Earnings but no payment reads as a withholding unless the document
        // says otherwise, so the reason cannot live in a covering email.
        XCTAssertTrue(text(of: try unrecouped.render()).contains("not yet recouped"))
    }

    // MARK: Aged debtors

    func testShortDebtorRowIsPaddedRatherThanShiftingColumns() throws {
        let report = AgedAnalysis(
            branding: brand,
            asAt: "31 July 2026",
            buckets: ["Current", "31–60", "61–90", "90+"],
            rows: [DebtorRow(account: "Northwind", amounts: ["£100.00"], total: "£100.00")]
        )
        let rendered = text(of: try report.render())

        // With only one amount given, the figure must stay under Current and
        // the total under Total — not slide left into the wrong bucket.
        XCTAssertTrue(rendered.contains("(Northwind) Tj"))
        XCTAssertEqual(rendered.components(separatedBy: "(\u{A3}100.00) Tj").count - 1, 2)
    }

    func testOverlongDebtorRowIsCutToTheBuckets() throws {
        let report = AgedAnalysis(
            branding: brand,
            asAt: "31 July 2026",
            buckets: ["Current", "90+"],
            rows: [DebtorRow(account: "Northwind", amounts: ["£1.00", "£2.00", "£3.00", "£4.00"], total: "£10.00")]
        )
        let rendered = text(of: try report.render())
        XCTAssertFalse(rendered.contains("(\u{A3}4.00) Tj"), "a figure with no column should not be drawn")
    }

    func testCreditorsIsTheSameReportRunTheOtherWay() throws {
        let owed = AgedAnalysis(
            branding: brand, kind: .creditors, asAt: "31 July 2026",
            buckets: ["Current", "90+"],
            rows: [DebtorRow(account: "Kestrel Audio", amounts: ["£500.00", ""], total: "£500.00")]
        )
        let rendered = text(of: try owed.render())

        XCTAssertTrue(rendered.contains("(AGED CREDITORS) Tj"))
        // A creditors report lists suppliers; calling the column "Account"
        // leaves the reader working out which side of the ledger it is.
        XCTAssertTrue(rendered.contains("(Supplier) Tj"))
        XCTAssertFalse(rendered.contains("(AGED DEBTORS) Tj"))
    }

    func testDebtorsRemainsTheDefault() throws {
        let owing = AgedAnalysis(
            branding: brand, asAt: "31 July 2026", buckets: ["Current"],
            rows: [DebtorRow(account: "Northwind", amounts: ["£1.00"], total: "£1.00")]
        )
        let rendered = text(of: try owing.render())
        XCTAssertTrue(rendered.contains("(AGED DEBTORS) Tj"))
        XCTAssertTrue(rendered.contains("(Account) Tj"))
    }

    // MARK: Consignments

    private var goods: [ConsignmentItem] {
        [ConsignmentItem(
            description: "Field recorder",
            commodityCode: "8519.81",
            countryOfOrigin: "Japan",
            quantity: "4 pcs",
            netWeight: "3.2 kg",
            grossWeight: "4.6 kg",
            unitPrice: "£880.00",
            amount: "£3,520.00",
            package: "1 of 3"
        )]
    }

    func testPackingListCarriesNoPrices() throws {
        let list = Consignment(
            branding: brand, kind: .packingList, number: "PL-1", date: "11 August 2026",
            exporter: Party(name: "ArrayPress Ltd", address: ["London"]),
            consignee: Party(name: "Kestrel GmbH", address: ["Frankfurt"]),
            items: goods,
            value: [("Total value", "£3,520.00")]
        )
        let rendered = text(of: try list.render())

        // Not a formatting choice: the list is handled by people who should
        // not be reading the seller's prices.
        XCTAssertFalse(rendered.contains("3,520.00"))
        XCTAssertFalse(rendered.contains("(Amount) Tj"))
        XCTAssertTrue(rendered.contains("(Gross) Tj"))
    }

    func testCommercialInvoiceCarriesPricesAndTheDeclaration() throws {
        let invoice = Consignment(
            branding: brand, kind: .commercialInvoice, number: "CI-1", date: "11 August 2026",
            exporter: Party(name: "ArrayPress Ltd", address: ["London"]),
            consignee: Party(name: "Kestrel GmbH", address: ["Frankfurt"]),
            items: goods,
            incoterm: "DAP Duisburg (Incoterms 2020)",
            value: [("Total value", "£3,520.00")]
        )
        let rendered = text(of: try invoice.render())
        XCTAssertTrue(rendered.contains("3,520.00"))
        XCTAssertTrue(rendered.contains("I declare"))
        XCTAssertTrue(rendered.contains("(Signature) Tj"))
    }

    func testTheDeclarationWrapsRatherThanRunningIntoTheMargin() throws {
        // Drawn with `cell` it went out as one line — about 435 points of
        // sentence against a 359-point box — because a cell aligns within its
        // box and draws past it. A sentence wraps.
        let invoice = Consignment(
            branding: brand, kind: .commercialInvoice, number: "CI-2",
            exporter: Party(name: "ArrayPress Ltd", address: ["London"]),
            consignee: Party(name: "Kestrel GmbH", address: ["Frankfurt"]),
            items: goods,
            value: [("Total value", "£3,520.00")]
        )
        let document = try invoice.render()

        let sentence = ShippingDocument.commercialInvoice.declaration
        XCTAssertFalse(document.drawnText.contains(sentence),
                       "the whole declaration went out as a single unwrapped line")
        XCTAssertTrue(document.drawnText.joined(separator: " ").contains(sentence),
                      "wrapping must not lose any of the wording")
    }

    func testPackageNumbersAreDrawnWhenGiven() throws {
        let list = Consignment(
            branding: brand, kind: .packingList, number: "PL-1",
            exporter: Party(name: "ArrayPress Ltd"),
            consignee: Party(name: "Kestrel GmbH"),
            items: goods
        )
        // Naming the column and then dropping every value shifted the whole
        // row one place left, which put commodity codes under Pkg.
        let rendered = text(of: try list.render())
        XCTAssertTrue(rendered.contains("(Pkg) Tj"))
        XCTAssertTrue(rendered.contains("(1 of 3) Tj"))
        XCTAssertTrue(rendered.contains("(8519.81) Tj"))
    }

    func testCountryOfOriginIsNotTruncated() throws {
        let invoice = Consignment(
            branding: brand, kind: .commercialInvoice, number: "CI-1",
            exporter: Party(name: "ArrayPress Ltd"),
            consignee: Party(name: "Kestrel GmbH"),
            items: [ConsignmentItem(
                description: "Windshield kit", commodityCode: "3926.90",
                countryOfOrigin: "United Kingdom", quantity: "6 pcs",
                netWeight: "2.4 kg", grossWeight: "3.8 kg",
                unitPrice: "£95.00", amount: "£570.00", package: "2 of 3"
            )]
        )
        // An origin cut to "Unite..." is the difference between goods clearing
        // and goods being held.
        XCTAssertTrue(text(of: try invoice.render()).contains("(United Kingdom) Tj"))
    }

    func testConsignmentNamesTheParticularsItIsMissing() throws {
        let bare = Consignment(
            branding: brand, kind: .commercialInvoice, number: "",
            exporter: Party(name: "ArrayPress Ltd"),
            consignee: Party(name: "Kestrel GmbH"),
            items: [ConsignmentItem(description: "Something")]
        )
        let warnings = bare.complianceWarnings()

        XCTAssertTrue(warnings.contains("document number"))
        XCTAssertTrue(warnings.contains("commodity code on every line"))
        XCTAssertTrue(warnings.contains("country of origin on every line"))
        XCTAssertTrue(warnings.contains("delivery term (Incoterm) and named place"))
        XCTAssertTrue(warnings.contains("reason for export"))
    }

    func testPackingListIsNotAskedForPrices() throws {
        let list = Consignment(
            branding: brand, kind: .packingList, number: "PL-1", date: "11 August 2026",
            exporter: Party(name: "ArrayPress Ltd", address: ["London"]),
            consignee: Party(name: "Kestrel GmbH", address: ["Frankfurt"]),
            items: goods,
            countryOfExport: "United Kingdom",
            countryOfDestination: "Germany"
        )
        let warnings = list.complianceWarnings()
        XCTAssertFalse(warnings.contains("total value"))
        XCTAssertFalse(warnings.contains("a value on every line"))
        XCTAssertTrue(warnings.isEmpty, "\(warnings)")
    }

    // MARK: Every template

    func testEveryTemplateProducesAReadableFile() throws {
        let documents: [Document] = [
            try Timesheet(branding: brand, worker: Party(name: "A"), period: "July",
                      entries: [TimeEntry(date: "1", description: "x", hours: "1")]).render(),
            try RoyaltyStatement(branding: brand, payee: Party(name: "B"), period: "July",
                             lines: [RoyaltyLine(source: "S", title: "T", net: "£1", earned: "£1")]).render(),
            try AgedAnalysis(branding: brand, asAt: "31 July", buckets: ["Current"],
                        rows: [DebtorRow(account: "C", amounts: ["£1"], total: "£1")]).render(),
            try Consignment(branding: brand, number: "1", exporter: Party(name: "D"),
                        consignee: Party(name: "E"), items: [ConsignmentItem(description: "F")]).render(),
        ]

        for document in documents {
            let data = document.render()
            XCTAssertTrue(String(decoding: data.prefix(8), as: UTF8.self).hasPrefix("%PDF-1."))
            XCTAssertTrue(String(decoding: data.suffix(8), as: UTF8.self).contains("%%EOF"))
            XCTAssertGreaterThan(document.pageCount(), 0)
        }
    }
}

// MARK: - The VAT notice

extension TemplateTests {

    /// Every straight line drawn on the page, as coordinate pairs.
    private func segments(_ data: Data) throws -> [(from: (Double, Double), to: (Double, Double))] {
        let raw = try XCTUnwrap(String(data: data, encoding: .isoLatin1))
        var found: [(from: (Double, Double), to: (Double, Double))] = []
        var pending: (Double, Double)?

        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 3, parts[2] == "m",
               let x = Double(parts[0]), let y = Double(parts[1]) {
                pending = (x, y)
            } else if parts.count == 3, parts[2] == "l",
                      let x = Double(parts[0]), let y = Double(parts[1]), let start = pending {
                found.append((from: start, to: (x, y)))
            }
        }
        return found
    }

    private func noticed() -> Invoice {
        Invoice(
            branding: Branding(name: "Meridian Studio Ltd"),
            number: "INV-1",
            from: Party(name: "S", address: ["1 Road"], taxID: "GB1"),
            to: Party(name: "B", address: ["2 Road"]),
            items: [LineItem(description: "Thing", amount: "£1.00")],
            totals: [("Subtotal", "£1.00")],
            vat: .smallBusiness,
            supplyDate: "1 August 2026",
            germanNotes: true
        )
    }

    func testTheNoticeIsAClosedBox() throws {
        // It was drawn on three sides, which reads as a box somebody forgot
        // to finish rather than as a box.
        let document = try noticed().render()
        let drawn = try segments(document.render())

        let left = document.left(), right = document.right()
        let verticals = drawn.filter { abs($0.from.0 - $0.to.0) < 0.01 }

        XCTAssertTrue(verticals.contains { abs($0.from.0 - left) < 0.01 },
                      "no left edge")
        XCTAssertTrue(verticals.contains { abs($0.from.0 - right) < 0.01 },
                      "no right edge — the box is open")
    }

    func testTheNoticeSitsInTheMiddleOfItsOwnRule() throws {
        // The version this replaced left sixteen points of air above the text
        // and four below it, so the block sat visibly high in its own rule.
        let document = try noticed().render()
        let data = document.render()
        let raw = try XCTUnwrap(String(data: data, encoding: .isoLatin1))

        // The notice's own baselines, found by the words on them rather than
        // by position — every other line on the page is somebody else's.
        var baselines: [Double] = []
        var pending: Double?
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 3, parts[2] == "Td", let y = Double(parts[1]) { pending = y }
            if line.contains("Tj"), line.contains("No VAT charged") || line.contains("UStG"),
               let y = pending {
                baselines.append(y)
            }
        }
        XCTAssertEqual(baselines.count, 2, "the notice should be two lines")

        let highest = try XCTUnwrap(baselines.max())
        let lowest = try XCTUnwrap(baselines.min())

        // Its own rules: the full-width ones immediately above and below.
        let rules = try segments(data)
            .filter { abs($0.from.1 - $0.to.1) < 0.01 && abs($0.to.0 - $0.from.0) > 400 }
            .map(\.from.1)

        let top = try XCTUnwrap(rules.filter { $0 > highest }.min())
        let bottom = try XCTUnwrap(rules.filter { $0 < lowest }.max())

        let above = top - highest
        let below = lowest - bottom

        // Not identical: a baseline sits above the descender, so the measured
        // gap below is to the bottom of the type rather than the top of it.
        // Within four points is the difference between centred and not.
        XCTAssertEqual(above, below, accuracy: 4,
                       "the notice is \(above) above and \(below) below its own rule")
    }
}

// MARK: - The wording, in the language that reads it

extension TemplateTests {

    private func noticed(_ treatment: VatTreatment,
                         in language: VatTreatment.Wording?) -> Invoice {
        Invoice(
            branding: Branding(name: "Meridian Studio Ltd"), number: "INV-1",
            from: Party(name: "S", address: ["1 Road"], taxID: "GB1"),
            to: Party(name: "B", address: ["2 Road"], taxID: "DE1"),
            items: [LineItem(description: "Thing", amount: "€1,00")],
            totals: [("Subtotal", "€1,00")],
            vat: treatment, supplyDate: "1 August 2026", wording: language
        )
    }

    func testTheEnglishIsAlwaysThere() throws {
        for language in VatTreatment.Wording.allCases {
            let text = try XCTUnwrap(
                PDFDocument(data: try noticed(.reverseCharge, in: language).render().render())?.string
            )
            XCTAssertTrue(text.contains("Reverse charge"), language.rawValue)
        }
    }

    func testEachLanguageSaysItInItsOwnLaw() throws {
        let expected: [VatTreatment.Wording: String] = [
            .german: "Steuerschuldnerschaft",
            .french: "Autoliquidation",
            .italian: "Inversione contabile",
            .spanish: "Inversión del sujeto pasivo",
            .dutch: "Btw verlegd",
        ]

        for (language, phrase) in expected {
            let text = try XCTUnwrap(
                PDFDocument(data: try noticed(.reverseCharge, in: language).render().render())?.string
            )
            XCTAssertTrue(text.contains(phrase), "\(language.rawValue) did not say \(phrase)")
        }
    }

    func testEachLanguageCitesItsOwnStatute() throws {
        // A citation to a directive is right everywhere and persuades nobody:
        // an authority checking this expects the article of its own code.
        let citations: [VatTreatment.Wording: String] = [
            .german: "§ 13b UStG", .french: "283-2 du CGI",
            .italian: "DPR 633/72", .spanish: "Ley 37/1992", .dutch: "Wet OB",
        ]

        for (language, citation) in citations {
            let notes = VatTreatment.reverseCharge.notes(also: language).joined(separator: " ")
            XCTAssertTrue(notes.contains(citation), "\(language.rawValue): \(notes)")
        }
    }

    func testEveryTreatmentHasWordingInEveryLanguage() throws {
        // Except standard, which needs none — VAT charged at the domestic
        // rate is the thing that requires no explanation.
        for language in VatTreatment.Wording.allCases {
            for treatment in VatTreatment.allCases where treatment != .standard {
                XCTAssertFalse(
                    language.notes(for: treatment).isEmpty,
                    "\(language.rawValue) has nothing for \(treatment.rawValue)"
                )
            }
            XCTAssertTrue(language.notes(for: .standard).isEmpty)
        }
    }

    func testTheOldGermanFlagStillWorks() throws {
        let invoice = Invoice(
            branding: Branding(name: "x"), number: "INV-1",
            from: Party(name: "S", address: ["1"], taxID: "GB1"),
            to: Party(name: "B", address: ["2"], taxID: "DE1"),
            items: [], totals: [("Subtotal", "€1,00")],
            vat: .reverseCharge, supplyDate: "1 Aug 2026", germanNotes: true
        )

        XCTAssertTrue(invoice.germanNotes)
        let text = try XCTUnwrap(PDFDocument(data: invoice.render().render())?.string)
        XCTAssertTrue(text.contains("Steuerschuldnerschaft"))
    }

    func testNoLanguageMeansEnglishAlone() throws {
        let text = try XCTUnwrap(
            PDFDocument(data: try noticed(.reverseCharge, in: nil).render().render())?.string
        )
        XCTAssertTrue(text.contains("Reverse charge"))
        XCTAssertFalse(text.contains("Autoliquidation"))
        XCTAssertFalse(text.contains("Steuerschuldnerschaft"))
    }
}
