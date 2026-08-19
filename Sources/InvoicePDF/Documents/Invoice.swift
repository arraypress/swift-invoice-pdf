//
//  Invoice.swift
//  TextPDF
//
//  Created by David Sherlock on 2026.
//
//  A complete invoice from data alone — no layout code at the call site.
//

import Foundation
import TextPDF

/// An invoice, credit note, quote or reminder — one layout, six headings.
///
/// The documents differ in wording and in which blocks appear, not in shape,
/// so they share a renderer rather than four near-copies that drift apart.
public enum DocumentKind: String, Sendable, CaseIterable, Codable {

    case invoice
    /// Issued to reverse an invoice. Never amend the original — sequential
    /// numbering forbids it, so a refund is a separate document that cites it.
    case creditNote
    case quote
    /// A pre-payment invoice. Not a tax invoice, and says so.
    case proforma
    case receipt
    case reminder

    /// Sent when *you* pay someone, itemising which of their invoices the
    /// payment covers. Not a tax document — theirs is.
    case remittance

    /// Issued by the buyer on the supplier's behalf, as a marketplace does.
    /// "Self-billing" must appear on the face of it, and both parties' VAT
    /// numbers are required.
    case selfBilling

    /// Accompanies goods. Shows what was sent, never what it cost — a
    /// delivery note goes in the box, and the recipient's warehouse has no
    /// business seeing the price.
    case deliveryNote

    /// Issued by the buyer, committing to purchase.
    case purchaseOrder

    /// Sent by the seller acknowledging an order before fulfilment.
    case orderConfirmation

    /// The counterpart to a credit note: charging more after the fact.
    case debitNote

    public var title: String {
        switch self {
        case .invoice: return "INVOICE"
        case .creditNote: return "CREDIT NOTE"
        case .quote: return "QUOTE"
        case .proforma: return "PROFORMA"
        case .receipt: return "RECEIPT"
        case .reminder: return "REMINDER"
        case .remittance: return "REMITTANCE ADVICE"
        case .selfBilling: return "SELF-BILLED INVOICE"
        case .deliveryNote: return "DELIVERY NOTE"
        case .purchaseOrder: return "PURCHASE ORDER"
        case .orderConfirmation: return "ORDER CONFIRMATION"
        case .debitNote: return "DEBIT NOTE"
        }
    }

    /// The label above the totals block.
    var totalLabel: String {
        switch self {
        case .creditNote: return "Total credited"
        case .debitNote: return "Total charged"
        case .purchaseOrder, .orderConfirmation: return "Order total"
        case .quote, .proforma: return "Total"
        case .receipt, .remittance: return "Total paid"
        default: return "Total due"
        }
    }

    /// Wording printed under the total, when the kind needs it.
    var standingNote: String? {
        switch self {
        case .creditNote:
            return "This credit note reverses the invoice referenced above. Retain both for your records."
        case .quote:
            return "This is a quotation, not a demand for payment. No VAT is due until an invoice is issued."
        case .proforma:
            return "Proforma invoice — not a VAT invoice. A tax invoice follows on payment."
        case .receipt:
            return "Paid in full. No further payment is due."
        case .deliveryNote:
            return "Please check the contents against this note and report any discrepancy within 7 days."
        case .orderConfirmation:
            return "This confirms your order. An invoice follows on despatch."
        case .debitNote:
            return "This debit note charges the additional amount shown against the document referenced above."
        case .remittance:
            return "This advice confirms payment of the invoices listed above. No action is required."
        case .selfBilling:
            // HMRC requires the words on the face of the document; without
            // them the recipient cannot rely on it.
            return "Self-billing. This invoice was raised by the customer on the supplier's behalf under a self-billing agreement."
        default:
            return nil
        }
    }

    /// Whether money appears at all.
    ///
    /// A delivery note travels with the goods, and the recipient's warehouse
    /// has no business seeing what the buyer paid. Suppressing the columns is
    /// the document's defining behaviour, not a styling choice.
    var showsMoney: Bool { self != .deliveryNote }

    /// Whether the mandatory-particulars check applies.
    ///
    /// A quote is not a tax document, so demanding a supply date on one would
    /// be a false warning.
    var isTaxDocument: Bool {
        switch self {
        case .invoice, .creditNote, .receipt, .selfBilling, .debitNote: return true
        // A remittance advice reports a payment against someone else's
        // invoice; the tax particulars belong on theirs, not on this.
        case .quote, .proforma, .reminder, .remittance,
             .deliveryNote, .purchaseOrder, .orderConfirmation: return false
        }
    }
}

/// A business document, rendered from data.
public struct Invoice: Sendable {

    /// What sort of document this is — invoice, credit note, quote.
    public let kind: DocumentKind

    /// The seller's identity on the page: logo, colours, typeface.
    public let branding: Branding

    /// The document number, exactly as it should print.
    public let number: String

    /// Who issued the document.
    public let from: Party

    /// Who it is addressed to.
    public let to: Party

    /// The lines being billed, in the order they appear.
    public let items: [LineItem]

    /// Subtotal rows, in order. A list of pairs rather than a dictionary,
    /// because two `Discount` lines are legitimate and a map cannot hold them.
    public let totals: [(label: String, value: String)]

    /// The headline total.
    public let total: [(label: String, value: String)]

    /// Dates, terms and references.
    public let details: [(label: String, value: String)]

    /// Free text under the table — terms, thanks, instructions.
    public let notes: String

    /// An optional stamp, e.g. `PAID` or `OVERDUE`.
    public let status: String

    /// The paper the document is set for.
    public let size: PageSize

    /// How VAT is treated, which drives the wording the law requires.
    public let vat: VatTreatment

    /// The tax breakdown by rate, where more than one applies.
    public let vatLines: [VatLine]

    /// Date of supply, which German law requires separately from the document
    /// date and which is the particular most often left off.
    public let supplyDate: String

    /// The document this one refers to — the original invoice for a credit
    /// note, or the overdue invoice for a reminder.
    public let reference: String

    /// Print the German wording as well as the English.
    ///
    /// Kept for the documents written before other languages existed;
    /// ``wording`` is the general form.
    public var germanNotes: Bool { wording == .german }

    /// A second language beside the English, where the document is going
    /// somewhere its authority reads its own law.
    public let wording: VatTreatment.Wording?

    /// A code to scan, printed beside the payment wording.
    public let paymentCode: PaymentCode?

    public init(
        kind: DocumentKind = .invoice,
        branding: Branding,
        number: String,
        from: Party,
        to: Party,
        items: [LineItem],
        totals: [(label: String, value: String)] = [],
        total: [(label: String, value: String)] = [],
        details: [(label: String, value: String)] = [],
        notes: String = "",
        status: String = "",
        size: PageSize = .a4,
        vat: VatTreatment = .standard,
        vatLines: [VatLine] = [],
        supplyDate: String = "",
        reference: String = "",
        germanNotes: Bool = false,
        wording: VatTreatment.Wording? = nil,
        paymentCode: PaymentCode? = nil
    ) {
        self.kind = kind
        self.branding = branding
        self.number = number
        self.from = from
        self.to = to
        self.items = items
        self.totals = totals
        self.total = total
        self.details = details
        self.notes = notes
        self.status = status
        self.size = size
        self.vat = vat
        self.vatLines = vatLines
        self.supplyDate = supplyDate
        self.reference = reference
        self.wording = wording ?? (germanNotes ? .german : nil)
        self.paymentCode = paymentCode
    }

    // MARK: Compliance

    /// Mandatory particulars that are missing.
    ///
    /// Checks against the fields §14 UStG and Article 226 of the VAT Directive
    /// require. A document missing any of them can be refused as evidence for
    /// the recipient's input-tax deduction — which makes it their problem and
    /// your support ticket.
    ///
    /// Not tax advice, and not exhaustive: it verifies the particulars this
    /// template can see, not whether the treatment chosen is correct.
    public func complianceWarnings() -> [String] {
        guard kind.isTaxDocument else { return [] }

        var missing: [String] = []

        if from.taxID.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("The supplier VAT or tax number is missing.")
        }
        if from.address.isEmpty {
            missing.append("The supplier address is missing.")
        }
        if to.address.isEmpty {
            missing.append("The customer address is missing.")
        }
        if number.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("A sequential document number is required.")
        }
        if supplyDate.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("The date of supply is required, separately from the document date.")
        }
        if vat.requiresBothVatNumbers, to.taxID.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("The customer VAT number is required for this VAT treatment.")
        }
        // A self-billed invoice carries both numbers whatever the treatment —
        // the supplier's is what makes it their invoice.
        if kind == .selfBilling, to.taxID.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("A self-billed invoice must show the supplier's VAT number.")
        }
        if kind == .creditNote, reference.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("A credit note must reference the invoice it reverses.")
        }
        if kind == .debitNote, reference.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("A debit note must reference the document it adjusts.")
        }
        if vatLines.count > 1 { return missing }

        if vat == .standard, vatLines.isEmpty, totals.isEmpty {
            missing.append("The taxable amount and VAT must be shown per rate.")
        }
        return missing
    }

    /// Mandatory particulars missing from a document that was actually drawn.
    ///
    /// ``complianceWarnings()`` inspects the data: it can tell you a reverse
    /// charge was declared, not that the words reached the page. This asks the
    /// finished document, which is the question that matters — a recipient's
    /// input-tax deduction turns on wording being *printed*, and a template
    /// that stopped drawing it would pass every check that only reads the
    /// invoice's fields.
    ///
    /// Still not tax advice. It verifies the particulars are present on the
    /// page, not that the treatment chosen was the right one.
    public func complianceWarnings(verifying document: Document) -> [String] {
        var missing = complianceWarnings()

        let page = document.drawnText.joined(separator: " ")

        // The wording that makes the document valid for the recipient.
        for note in vat.notes(german: germanNotes) where !page.contains(note) {
            missing.append("The wording \"\(note)\" is required and did not reach the page.")
        }

        if kind.isTaxDocument, !number.isEmpty, !page.contains(number) {
            missing.append("The document number did not reach the page.")
        }
        if kind.isTaxDocument, !supplyDate.isEmpty, !page.contains(supplyDate) {
            missing.append("The date of supply did not reach the page.")
        }
        for line in total where !page.contains(line.value) {
            missing.append("The total \"\(line.value)\" did not reach the page.")
        }
        return missing
    }

    // MARK: Rendering

    /// Lays the document out.
    /// Lays the document out.
    ///
    /// The font, if any, has to be in place before anything is drawn — text is
    /// committed to the content stream as it is laid out, so a font attached
    /// afterwards arrives too late to be used.
    public func render(embedding font: EmbeddedFont? = nil) throws -> Document {
        try render(in: nil, fallback: font)
    }

    /// The same, set in a family.
    ///
    /// Where `family` is the document's type and draws everything, `fallback`
    /// is reached for only when the family cannot — a Cyrillic customer name
    /// against a brand face that has no Cyrillic in it.
    ///
    /// - Throws: When the branding's typeface files cannot be loaded. A
    ///   missing brand font is reported, not substituted — a document
    ///   silently set in Helvetica looks fine to everyone except the person
    ///   whose brand it is.
    public func render(in family: FontFamily?, fallback: EmbeddedFont? = nil) throws -> Document {
        let pdf = Document(size: size, orientation: .portrait, margin: 48, fontSize: 9.5, leading: 13)
        pdf.family = try family ?? branding.family()
        pdf.embeddedFont = fallback
        pdf.language = germanNotes ? "de" : "en"

        masthead(pdf)
        parties(pdf)
        itemTable(pdf)
        vatBreakdown(pdf)
        totalsBlock(pdf)
        vatNotes(pdf)
        paymentNotes(pdf)

        let brand = branding
        pdf.onEachPage { doc, page, total in
            if !brand.footnotes.isEmpty {
                doc.line(from: doc.left(), 58, to: doc.right(), 58, color: brand.hairline)
                var y = 46.0
                for note in brand.footnotes {
                    doc.textAt(note, x: doc.left(), y: y, size: 7.5, font: .helvetica, color: .grey(150))
                    y -= 10
                }
            }
            if total > 1 {
                doc.textAt(
                    "Page \(page) of \(total)",
                    x: doc.left(), y: 46, size: 7.5, font: .helvetica,
                    color: .grey(150), align: .right, boxWidth: doc.contentWidth()
                )
            }
        }
        return pdf
    }

    /// Renders and writes to a file.
    ///
    /// Throws where `render` cannot: a branding typeface whose files will not
    /// load is reported here rather than silently set in Helvetica.
    @discardableResult
    public func save(to url: URL) throws -> Int {
        try render().save(to: url, metadata: [
            "Title": "\(kind.title) \(number)",
            "Author": from.name,
            "Subject": "\(kind.title) for \(to.name)",
        ])
    }

    // MARK: Sections

    private func masthead(_ pdf: Document) {
        let top = pdf.height() - 48
        var x = pdf.left()

        if let logoPath = branding.logoPath, !logoPath.isEmpty {
            pdf.svgPath(
                logoPath, x: x, y: top - 34,
                scale: 34 / branding.logoBox,
                color: branding.accentColor,
                svgHeight: branding.logoBox
            )
            x += 46
        }

        pdf.textAt(branding.name.uppercased(), x: x, y: top - 14, size: 15,
                   font: .helveticaBold, color: branding.accentColor)

        if !branding.tagline.isEmpty {
            pdf.textAt(branding.tagline, x: x, y: top - 27, size: 8, font: .helvetica, color: branding.muted)
        }

        // Title, reference and status stack down the right edge. Each needs
        // its own band — overlaying them puts the stamp across the reference
        // number, which is the one thing a customer has to quote back.
        // 22 with a little tracking rather than 26: the title is the page's
        // label, not its headline — at 26 it shouted the brand name down, and
        // the reading order should be brand, then title, then number.
        pdf.textAt(kind.title, x: pdf.left(), y: top - 20, size: 22,
                   font: .helveticaBold, color: branding.ink, align: .right,
                   boxWidth: pdf.contentWidth(), tracking: 1)
        pdf.textAt(number, x: pdf.left(), y: top - 34, size: 8,
                   font: .helvetica, color: branding.muted, align: .right, boxWidth: pdf.contentWidth())

        var ruleY = top - 66
        if !status.isEmpty {
            stamp(pdf, y: top - 58)
            ruleY = top - 78
        }

        pdf.move(to: ruleY)
        pdf.line(from: pdf.left(), pdf.cursor(), to: pdf.right(), pdf.cursor(), color: branding.ink, thickness: 0.75)
        pdf.move(to: pdf.cursor() - 28)
    }

    /// An outlined status stamp.
    ///
    /// Outlined rather than filled: reversed-out white text on a light accent
    /// is unreadable, and on a mono palette it disappears entirely.
    private func stamp(_ pdf: Document, y: Double) {
        let label = status.uppercased()
        // Measured by the document, not the base font: with a family attached
        // the label is drawn in the family's bold, and a wider face measured
        // as Helvetica overruns the box drawn around it.
        let width = pdf.width(of: label, size: 8, font: .helveticaBold) + 22
        let height = 16.0
        let left = pdf.right() - width
        let bottom = y - 4

        pdf.line(from: left, bottom, to: left + width, bottom, color: branding.ink, thickness: 0.75)
        pdf.line(from: left, bottom + height, to: left + width, bottom + height, color: branding.ink, thickness: 0.75)
        pdf.line(from: left, bottom, to: left, bottom + height, color: branding.ink, thickness: 0.75)
        pdf.line(from: left + width, bottom, to: left + width, bottom + height, color: branding.ink, thickness: 0.75)

        pdf.textAt(
            label, x: left,
            y: bottom + ((height - Font.helveticaBold.capHeight(8)) / 2),
            size: 8, font: .helveticaBold, color: branding.ink,
            align: .center, boxWidth: width
        )
    }

    private func parties(_ pdf: Document) {
        let top = pdf.cursor()
        let column = pdf.contentWidth() / 2

        let heading: String
        switch kind {
        case .remittance: heading = "PAID TO"
        case .selfBilling, .purchaseOrder: heading = "SUPPLIER"
        case .deliveryNote: heading = "DELIVER TO"
        default: heading = "BILLED TO"
        }
        pdf.textAt(heading, x: pdf.left(), y: top, size: 7, font: .helveticaBold, color: branding.muted)
        pdf.textAt(to.name, x: pdf.left(), y: top - 16, size: 11, font: .helveticaBold, color: branding.ink)

        var y = top - 29
        for line in to.linkedLines() {
            if line.url.isEmpty {
                pdf.textAt(line.text, x: pdf.left(), y: y, size: 9,
                           font: .helvetica, color: branding.muted)
            } else {
                pdf.linked(line.text, url: line.url, x: pdf.left(), y: y, size: 9,
                           font: .helvetica, color: branding.muted)
            }
            y -= 11.5
        }

        let detailX = pdf.left() + column + 20
        let detailWidth = column - 20

        // The supply date is a mandatory particular in its own right and the
        // one most often left off, so it is added rather than relying on the
        // caller to remember it.
        var rows = details
        if !supplyDate.isEmpty, !rows.contains(where: { $0.label == "Date of supply" }) {
            rows.append((label: "Date of supply", value: supplyDate))
        }
        if !reference.isEmpty, !rows.contains(where: { $0.label.lowercased().contains("reference") }) {
            rows.append((label: kind == .creditNote ? "Original invoice" : "Reference", value: reference))
        }

        if !rows.isEmpty {
            pdf.textAt("DETAILS", x: detailX, y: top, size: 7, font: .helveticaBold, color: branding.muted)
            var detailY = top - 16
            for row in rows {
                pdf.textAt(row.label, x: detailX, y: detailY, size: 9, font: .helvetica, color: branding.muted)
                pdf.textAt(row.value, x: detailX, y: detailY, size: 9, font: .helveticaBold,
                           color: branding.ink, align: .right, boxWidth: detailWidth)
                detailY -= 13
            }
            y = min(y, detailY)
        }
        pdf.move(to: y - 18)
    }

    private func itemTable(_ pdf: Document) {
        guard !items.isEmpty else { return }

        let hasUnit = items.contains { !$0.unitPrice.isEmpty }

        let headers: [String]
        let fractions: [Double]
        let aligns: [Int: Align]

        if !kind.showsMoney {
            headers = ["Description", "Qty"]
            fractions = [0.85, 0.15]
            aligns = [1: .center]
        } else if hasUnit {
            headers = ["Description", "Qty", "Unit price", "Amount"]
            fractions = [0.50, 0.10, 0.20, 0.20]
            aligns = [1: .center, 2: .right, 3: .right]
        } else {
            headers = ["Description", "Qty", "Amount"]
            fractions = [0.66, 0.14, 0.20]
            aligns = [1: .center, 2: .right]
        }

        let rows = items.map { item in
            (cells: !kind.showsMoney
                ? [item.description, item.quantity]
                : hasUnit
                    ? [item.description, item.quantity, item.unitPrice, item.amount]
                    : [item.description, item.quantity, item.amount],
             note: item.note)
        }
        itemGrid(pdf, headers: headers, fractions: fractions, aligns: aligns, rows: rows)
    }

    /// The item table, drawn by hand rather than through `Table`.
    ///
    /// `Table` sets one line per row, and a line's detail — hours, a date
    /// range, a licence period — read as part of what was sold when it sat
    /// inline after the description. It goes underneath instead, in the
    /// quiet type a meta line gets. The grid itself matches `Table`'s
    /// drawing — the same heights, rules and padding — so it sits beside
    /// every other table in the family without looking like a cousin.
    private func itemGrid(
        _ pdf: Document,
        headers: [String],
        fractions: [Double],
        aligns: [Int: Align],
        rows: [(cells: [String], note: String)]
    ) {
        let size = 9.0
        let height = 22.0
        // What a note adds to its row, and where it hangs below the
        // description's baseline.
        let noteExtra = 11.0
        let noteDrop = 9.5
        let padding = 6.0
        let widths = fractions.map { $0 * pdf.contentWidth() }

        func line(_ cells: [String], font: Font, color: Color?) {
            var x = pdf.left()
            let y = pdf.cursor()
            let last = cells.count - 1

            for (index, cell) in cells.enumerated() {
                let width = index < widths.count ? widths[index] : 0
                guard width > 0 else { continue }

                let leading = index == 0 ? 0 : padding
                let trailing = index == last ? 0 : padding
                let inner = width - leading - trailing

                pdf.textAt(
                    pdf.fit(cell, into: inner, size: size, font: font),
                    x: x + leading,
                    y: y - font.bandBaseline(bandHeight: height, size: size),
                    size: size, font: font, color: color,
                    align: aligns[index] ?? .left, boxWidth: inner
                )
                x += width
            }
        }

        func header() {
            pdf.rect(x: pdf.left(), y: pdf.cursor() - height,
                     width: pdf.contentWidth(), height: height, color: branding.wash)
            let top = pdf.cursor()
            line(headers, font: .helveticaBold, color: .grey(30))
            pdf.gap(height)
            pdf.line(from: pdf.left(), top, to: pdf.right(), top, color: .grey(60), thickness: 0.75)
            pdf.line(from: pdf.left(), pdf.cursor(), to: pdf.right(), pdf.cursor(),
                     color: .grey(60), thickness: 0.75)
        }

        header()
        for row in rows {
            let tall = row.note.isEmpty ? height : height + noteExtra

            // Break with the header repeated, exactly as `Table` does, or
            // everything past page one is a column of unlabelled numbers.
            if pdf.remaining() < tall + height {
                pdf.pageBreak()
                header()
            }

            let top = pdf.cursor()
            line(row.cells, font: .helvetica, color: nil)

            if !row.note.isEmpty {
                let baseline = top - Font.helvetica.bandBaseline(bandHeight: height, size: size)
                pdf.textAt(
                    pdf.fit(row.note, into: widths[0], size: 7.5, font: .helvetica),
                    x: pdf.left(), y: baseline - noteDrop,
                    size: 7.5, font: .helvetica, color: branding.muted
                )
            }
            pdf.move(to: top - tall)
        }
    }

    /// Whether the per-rate breakdown earns its place on the page.
    ///
    /// It exists because §14 UStG and Article 226 require the taxable amount
    /// shown against each rate when rates are *mixed*. With a single standard
    /// rate it repeats the totals block verbatim — the same two figures, in a
    /// column that lines up with nothing — so it is omitted.
    ///
    /// A non-standard treatment keeps it even at one rate: the row is what
    /// evidences the zero rating.
    var showsVatBreakdown: Bool {
        guard !vatLines.isEmpty else { return false }
        return vatLines.count > 1 || vat != .standard
    }

    private func vatBreakdown(_ pdf: Document) {
        guard showsVatBreakdown else { return }

        pdf.gap(18)
        pdf.breakIfNeeded(90)

        let width = pdf.contentWidth() * 0.55
        pdf.cell("VAT BREAKDOWN", x: pdf.left(), boxWidth: width, size: 7,
                 font: .helveticaBold, color: branding.muted)
        pdf.gap(14)

        let table = Table(headers: ["Rate", "Net", "VAT"])
        table.widths([0.4, 0.3, 0.3]).align([1: .right, 2: .right]).rowHeight(18)

        for line in vatLines {
            let rate = line.label.isEmpty ? line.rate : "\(line.label) (\(line.rate))"
            table.row([rate, line.net, line.vat])
        }

        // The cursor is wherever the table left it — which, when the table
        // broke to a new page, is near the top of that page. Clamping it back
        // to where this page started was the bug: it dragged the cursor to
        // the bottom of the fresh page and everything after arrived a page
        // late, below most of a page of nothing.
        table.draw(pdf, size: 8.5, headerFill: branding.wash)
    }

    private func totalsBlock(_ pdf: Document) {
        guard kind.showsMoney else {
            if let standing = kind.standingNote {
                pdf.gap(20)
                pdf.block(standing, x: pdf.left(), width: pdf.contentWidth(),
                          size: 8.5, font: .helvetica, color: branding.muted, leading: 12)
            }
            return
        }

        let width = pdf.contentWidth() * 0.42
        let x = pdf.right() - width

        pdf.gap(14)

        for row in totals {
            pdf.breakIfNeeded(60)
            pdf.cell(row.label, x: x, boxWidth: width, size: 9, font: .helvetica, color: branding.muted)
            pdf.cell(row.value, x: x, boxWidth: width, size: 9, font: .helvetica, color: branding.ink, align: .right)
            pdf.gap(15)
        }

        guard !total.isEmpty else { return }

        // A rule and a change of weight, rather than a filled block. It reads
        // as clearly, prints the same on any device, and cannot look subtly
        // wrong the way a band of colour with text in it can.
        pdf.gap(6)
        pdf.line(from: x, pdf.cursor(), to: pdf.right(), pdf.cursor(), color: branding.ink, thickness: 1)
        pdf.gap(20)

        for row in total {
            let baseline = pdf.cursor()
            pdf.textAt(row.label, x: x, y: baseline, size: 11, font: .helveticaBold, color: branding.ink)
            pdf.textAt(row.value, x: x, y: baseline, size: 14, font: .helveticaBold,
                       color: branding.ink, align: .right, boxWidth: width)
            pdf.gap(12)
            pdf.line(from: x, pdf.cursor(), to: pdf.right(), pdf.cursor(), color: branding.hairline, thickness: 0.5)
            pdf.gap(14)
        }

        if let standing = kind.standingNote {
            pdf.gap(4)
            pdf.block(standing, x: pdf.left(), width: pdf.contentWidth(),
                      size: 8.5, font: .helvetica, color: branding.muted, leading: 12)
        }
    }

    /// The mandatory VAT wording, printed prominently rather than buried,
    /// because its absence is what invalidates the recipient's deduction.
    private func vatNotes(_ pdf: Document) {
        let notes = vat.notes(also: wording)
        guard !notes.isEmpty else { return }

        // The box is measured from its content rather than from a guess:
        // the same padding above and below, and an inner width that allows
        // for the indent on both sides. The version this replaces used a
        // constant for the height and started the text two points below the
        // cursor, which left sixteen points of air at the top against four at
        // the bottom — the block sat visibly high in its own rule.
        let padding = 11.0
        let indent = 15.0
        let inner = pdf.contentWidth() - indent * 2

        let content = notes.reduce(0.0) { total, note in
            total + pdf.blockHeight(note, size: 8.5, width: inner, leading: 12)
        }
        let height = content + padding * 2

        pdf.gap(24)
        pdf.breakIfNeeded(height + 16)

        let top = pdf.cursor()
        let bottom = top - height

        pdf.line(from: pdf.left(), top, to: pdf.right(), top,
                 color: branding.hairline, thickness: 0.5)
        pdf.line(from: pdf.left(), bottom, to: pdf.right(), bottom,
                 color: branding.hairline, thickness: 0.5)

        // Closed on the right. Three sides read as a box somebody forgot to
        // finish; four read as a box.
        pdf.line(from: pdf.right(), top, to: pdf.right(), bottom,
                 color: branding.hairline, thickness: 0.5)

        // A heavier stub on the left edge draws the eye without needing
        // colour, which matters because this is the wording that makes the
        // document valid for the recipient's deduction.
        pdf.line(from: pdf.left(), top, to: pdf.left(), bottom,
                 color: branding.ink, thickness: 2)

        pdf.move(to: top - padding)
        for (index, note) in notes.enumerated() {
            pdf.block(note, x: pdf.left() + indent, width: inner, size: 8.5,
                      font: index == 0 ? .helveticaBold : .helvetica,
                      color: branding.ink, leading: 12)
        }
        pdf.move(to: bottom)
    }

    private func paymentNotes(_ pdf: Document) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || paymentCode != nil else { return }

        // The code sits against the right edge with the wording beside it, so
        // the two read as one instruction rather than as a note and a
        // decoration. Sized to be scanned from a printed page at arm's length.
        let code = 92.0
        let gutter = 18.0
        let hasCode = paymentCode != nil
        let width = hasCode ? pdf.contentWidth() - code - gutter : pdf.contentWidth()

        pdf.gap(26)
        pdf.breakIfNeeded(hasCode ? code + 46 : 70)

        pdf.line(from: pdf.left(), pdf.cursor() + 12, to: pdf.right(), pdf.cursor() + 12,
                 color: branding.hairline, thickness: 0.5)
        pdf.gap(6)

        let notesHeading: String
        switch kind {
        case .quote: notesHeading = "TERMS"
        case .remittance: notesHeading = "PAYMENT DETAILS"
        default: notesHeading = "PAYMENT"
        }
        pdf.cell(notesHeading, x: pdf.left(), boxWidth: 200, size: 7,
                 font: .helveticaBold, color: branding.muted)
        pdf.gap(14)

        let top = pdf.cursor()

        if !trimmed.isEmpty {
            pdf.block(trimmed, x: pdf.left(), width: width,
                      size: 8.5, font: .helvetica, color: branding.ink, leading: 12)
        }

        guard let paymentCode else { return }

        // Drawn from the top of the block rather than after it, so a long
        // payment note does not push the code down the page on its own.
        let drawn = pdf.qr(paymentCode.payload, x: pdf.right() - code, y: top - code,
                           size: code, color: branding.ink)

        if drawn {
            pdf.textAt(paymentCode.caption, x: pdf.right() - code, y: top - code - 11,
                       size: 7, color: branding.muted, align: .center, boxWidth: code)
        }

        // Whichever ran longer decides where the page carries on.
        pdf.move(to: min(pdf.cursor(), top - code - (drawn ? 18 : 0)))
    }
}
