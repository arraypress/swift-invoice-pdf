//
//  PaymentCodeTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import PDFKit
import XCTest
@testable import InvoicePDF
import TextPDF

final class PaymentCodeTests: XCTestCase {

    private func invoice(code: PaymentCode?, notes: String = "Payment by bank transfer.") -> Invoice {
        Invoice(
            branding: Branding(name: "Meridian Studio Ltd"),
            number: "INV-2026-0044",
            from: Party(name: "Meridian Studio Ltd", address: ["71 Shelton Street"], taxID: "GB1"),
            to: Party(name: "Klangwerk GmbH", address: ["Oranienburger Str. 87"]),
            items: [LineItem(description: "Licence", amount: "€149,00")],
            totals: [("Subtotal", "€149,00")],
            total: [("Total due", "€149,00")],
            notes: notes,
            supplyDate: "31 July 2026",
            paymentCode: code
        )
    }

    /// Reads the code off the finished page, the way a phone would.
    private func scan(_ data: Data) throws -> String? {
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        var box = CGRect(x: 0, y: 0, width: 1400, height: 1980)
        let image = try XCTUnwrap(
            page.thumbnail(of: box.size, for: .mediaBox)
                .cgImage(forProposedRect: &box, context: nil, hints: nil)
        )
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature]
        return features?.first?.messageString
    }

    // MARK: The EPC payload

    func testTheEPCPayloadIsTheSpecificationsShape() throws {
        let code = try XCTUnwrap(PaymentCode.epc(
            beneficiary: "Meridian Studio Ltd",
            iban: "DE89 3704 0044 0532 0130 00",
            amount: 898.80,
            bic: "COBADEFFXXX",
            reference: "INV-2026-0044"
        ))

        let lines = code.payload.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 11, "an app counts the lines to find its fields")
        XCTAssertEqual(lines[0], "BCD")
        XCTAssertEqual(lines[1], "002")
        XCTAssertEqual(lines[2], "1")
        XCTAssertEqual(lines[3], "SCT")
        XCTAssertEqual(lines[4], "COBADEFFXXX")
        XCTAssertEqual(lines[5], "Meridian Studio Ltd")
        XCTAssertEqual(lines[6], "DE89370400440532013000", "the spaces should come out of the IBAN")
        XCTAssertEqual(lines[7], "EUR898.80")
        XCTAssertEqual(lines[10], "INV-2026-0044")
    }

    func testTheAmountIsEuroAndTwoPlaces() throws {
        let code = try XCTUnwrap(PaymentCode.epc(beneficiary: "A", iban: "DE89370400440532013000",
                                                 amount: 1234.5))
        XCTAssertTrue(code.payload.contains("EUR1234.50"), code.payload)
        XCTAssertFalse(code.payload.contains("1,234"), "a separator reached the payload")
    }

    func testAnOpenAmountIsAllowed() throws {
        // What a part-paid invoice wants: the payer types what they are paying.
        let code = try XCTUnwrap(PaymentCode.epc(beneficiary: "A", iban: "DE89370400440532013000"))
        XCTAssertEqual(code.payload.components(separatedBy: "\n")[7], "")
    }

    func testTheRulesThatBiteAreEnforced() {
        let iban = "DE89370400440532013000"

        XCTAssertNil(PaymentCode.epc(beneficiary: "  ", iban: iban), "no beneficiary")
        XCTAssertNil(PaymentCode.epc(beneficiary: String(repeating: "A", count: 71), iban: iban),
                     "a name over 70 characters shows an error rather than a payment")
        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: "DE89"), "an IBAN that short is not one")
        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: iban,
                                     reference: String(repeating: "R", count: 141)),
                     "a reference over 140 characters")
        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: iban, amount: 0), "nothing to pay")
        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: iban, amount: -5), "a negative payment")
    }

    func testTheAmountBoundsApplyToWhatIsWritten() {
        // The bounds are checked after rounding, because rounding is what the
        // payload carries: 999999999.999 slipped under a pre-rounding cap and
        // came out EUR1000000000.00 — a cent over what the specification
        // allows — and 0.004 was a positive amount that rounded to a payment
        // of nothing.
        let iban = "DE89370400440532013000"

        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: iban, amount: Decimal(string: "999999999.999")!),
                     "over the ceiling once rounded")
        XCTAssertNil(PaymentCode.epc(beneficiary: "A", iban: iban, amount: Decimal(string: "0.004")!),
                     "rounds to a payment of nothing")

        // The edges themselves are payments.
        XCTAssertEqual(
            PaymentCode.epc(beneficiary: "A", iban: iban, amount: Decimal(string: "999999999.99")!)?
                .payload.components(separatedBy: "\n")[7],
            "EUR999999999.99"
        )
        XCTAssertEqual(
            PaymentCode.epc(beneficiary: "A", iban: iban, amount: Decimal(string: "0.01")!)?
                .payload.components(separatedBy: "\n")[7],
            "EUR0.01"
        )
    }

    func testItScansBackFromAPage() throws {
        let code = try XCTUnwrap(PaymentCode.epc(
            beneficiary: "Meridian Studio Ltd", iban: "DE89370400440532013000",
            amount: 898.80, reference: "INV-2026-0044"
        ))

        let pdf = Document()
        pdf.qr(code.payload, x: 60, y: 500, size: 150)
        XCTAssertEqual(try scan(pdf.render()), code.payload)
    }

    // MARK: On the invoice

    func testTheCodeReachesTheFinishedInvoice() throws {
        // The whole point: render the document, photograph it, get the
        // payment details back.
        let code = try XCTUnwrap(PaymentCode.epc(
            beneficiary: "Meridian Studio Ltd", iban: "DE89370400440532013000",
            amount: 149, reference: "INV-2026-0044"
        ))

        let data = try invoice(code: code).render().render()
        XCTAssertEqual(try scan(data), code.payload)
    }

    func testTheCaptionIsPrintedUnderIt() throws {
        let code = PaymentCode("https://arraypress.com/pay/INV-1", caption: "Pay online")
        let text = try XCTUnwrap(PDFDocument(data: invoice(code: code).render().render())?.string)

        XCTAssertTrue(text.contains("Pay online"), "somebody who cannot scan it learns nothing")
    }

    func testAnInvoiceWithoutOneDrawsNothing() throws {
        // Counted rather than looked for: a rectangle on its own is a table
        // stripe or a panel, and a code is hundreds of them.
        func squares(_ invoice: Invoice) throws -> Int {
            let raw = try XCTUnwrap(String(data: invoice.render().render(), encoding: .isoLatin1))
            return raw.components(separatedBy: " re\n").count - 1
        }

        let plain = try squares(invoice(code: nil))
        let coded = try squares(invoice(code: PaymentCode("https://arraypress.com/pay/1")))

        XCTAssertLessThan(plain, 30, "an invoice with no code is drawing hundreds of squares")
        XCTAssertGreaterThan(coded - plain, 100, "the code added no squares")
    }

    func testTheWordingAndTheCodeDoNotCollide() throws {
        // The note is set to a narrower measure when a code is beside it.
        let code = PaymentCode("https://arraypress.com/pay/INV-1")
        let long = String(repeating: "Payment by SEPA credit transfer, quoting the number. ", count: 4)

        let data = try invoice(code: code, notes: long).render().render()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))

        // Where the code is, no words: a scanner needs the square clean.
        let square = CGRect(x: page.bounds(for: .mediaBox).maxX - 140,
                            y: 60, width: 120, height: 200)
        let inside = page.selection(for: square).flatMap { $0.string } ?? ""
        XCTAssertTrue(inside.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "text ran under the code: \(inside)")
        XCTAssertEqual(try scan(data), code.payload, "and it still scans")
    }

    func testAnUnscannableCodeDoesNotLeaveACaptionBehind() throws {
        // A caption under nothing is worse than no caption.
        let code = PaymentCode(String(repeating: "A", count: 8_000), caption: "Scan to pay")
        let text = try XCTUnwrap(PDFDocument(data: invoice(code: code).render().render())?.string)

        XCTAssertFalse(text.contains("Scan to pay"))
    }

    func testEveryDocumentKindCanCarryOne() throws {
        // A reminder wants one more than an invoice does.
        let code = PaymentCode("https://arraypress.com/pay/INV-1")
        for kind in [DocumentKind.invoice, .reminder, .proforma, .quote] {
            let document = try Invoice(
                kind: kind, branding: Branding(name: "x"), number: "N-1",
                from: Party(name: "S", address: ["1"], taxID: "GB1"),
                to: Party(name: "B", address: ["2"]),
                items: [LineItem(description: "Thing", amount: "£1.00")],
                totals: [("Subtotal", "£1.00")],
                notes: "Payment by bank transfer.",
                supplyDate: "1 Aug 2026",
                paymentCode: code
            ).render().render()

            XCTAssertEqual(try scan(document), code.payload, kind.rawValue)
        }
    }
}
