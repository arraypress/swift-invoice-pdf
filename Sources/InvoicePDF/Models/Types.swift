//
//  Types.swift
//  TextPDF
//
//  Created by David Sherlock on 2026.
//
//  The value types every document template shares.
//
//  Everything money-shaped is a pre-formatted string, deliberately. Rendering
//  an amount correctly means knowing the currency's decimal exponent, its
//  thousands convention and its symbol placement, and a layout type has no
//  business guessing at any of that. Format it where the money lives and pass
//  the result.
//

import Countries
import Foundation
import TextPDF

// MARK: - Party

/// A business or person on a document.
public struct Party: Sendable, Equatable, Codable {

    public let name: String
    public let address: [String]
    public let email: String
    public let taxID: String

    /// Where they are, as an ISO 3166-1 code.
    ///
    /// Not printed — the address block already says it, in whatever wording
    /// the writer chose. This is for the machine-readable half, which has one
    /// place for a country and wants two letters in it: an e-invoice without
    /// the seller's country is rejected outright, by rule BR-09 of EN 16931.
    ///
    /// It is stated rather than read off the last line of the address,
    /// because reading it off is guesswork that succeeds quietly. An address
    /// ending "London WC2H 9JQ" has no country in it at all, and one ending
    /// "Sacramento, CA" has a country code in it that means Canada.
    public let country: Country?

    public init(
        name: String,
        address: [String] = [],
        email: String = "",
        taxID: String = "",
        country: Country? = nil
    ) {
        self.name = name
        self.address = address
        self.email = email
        self.taxID = taxID
        self.country = country
    }

    /// The address block, with a link where a line has somewhere to go.
    ///
    /// An invoice is read from a screen at least as often as from paper, and
    /// the supplier's email address is the one thing on it a recipient
    /// actually needs to act on when something is wrong.
    public func linkedLines(vatLabel: String = "VAT") -> [(text: String, url: String)] {
        var out = address.map { (text: $0, url: "") }
        if !email.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((email, "mailto:\(email.trimmingCharacters(in: .whitespaces))"))
        }
        if !taxID.isEmpty { out.append(("\(vatLabel) \(taxID)", "")) }
        return out.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The address block, one string per line.
    public func lines(vatLabel: String = "VAT") -> [String] {
        var lines = address
        if !email.isEmpty { lines.append(email) }
        if !taxID.isEmpty { lines.append("\(vatLabel) \(taxID)") }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Line item

/// One billable line.
public struct LineItem: Sendable, Equatable, Codable {

    public let description: String
    public let amount: String
    public let quantity: String
    public let unitPrice: String

    /// An optional second phrase, set alongside the description.
    public let note: String

    public init(
        description: String,
        amount: String,
        quantity: String = "1",
        unitPrice: String = "",
        note: String = ""
    ) {
        self.description = description
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.note = note
    }
}

// MARK: - VAT

/// A net amount, the rate applied to it, and the tax that produced.
///
/// Required as soon as a document mixes rates — §14(1) UStG and Article 226 of
/// the VAT Directive both want the taxable amount shown per rate, not one
/// combined tax figure.
public struct VatLine: Sendable, Equatable, Codable {

    public let rate: String
    public let net: String
    public let vat: String
    public let label: String

    public init(rate: String, net: String, vat: String, label: String = "") {
        self.rate = rate
        self.net = net
        self.vat = vat
        self.label = label
    }
}

/// How VAT is being handled.
///
/// Where VAT is not charged at the normal domestic rate, the document has to
/// say why — and in most of the EU it has to say why in specific words. A
/// document missing that wording can be refused as evidence for the
/// recipient's input-tax deduction, which turns a formatting oversight into
/// their tax problem and your support ticket.
///
/// **This is not tax advice.** Which treatment applies depends on facts this
/// library cannot see. It only makes sure the note you chose is printed
/// correctly and prominently.
public enum VatTreatment: String, Sendable, CaseIterable, Codable {

    /// Ordinary domestic VAT at the applicable rate.
    case standard

    /// Cross-border B2B supply where the customer accounts for the VAT.
    case reverseCharge

    /// Zero-rated intra-community supply of goods.
    case intraCommunitySupply

    /// Supply to a customer outside the EU.
    case export

    /// Small-business exemption — §19 UStG in Germany.
    case smallBusiness

    /// Exempt for another reason.
    case exempt

    /// The wording that must appear on the document.
    /// The language a document adds beside its English wording.
    ///
    /// The wording is not decoration: where VAT is not charged at the
    /// domestic rate, the phrase and its citation are what make the document
    /// evidence for the recipient's deduction. A tax authority reading it
    /// expects the words its own law uses.
    ///
    /// **Not legal advice, and worth a professional's eye before you rely on
    /// it.** These are the standard formulations and the articles they cite,
    /// which are published and formulaic — but a wrong phrase in a language
    /// you do not read is worse than an English one you do.
    public enum Wording: String, Sendable, CaseIterable {

        case german, french, italian, spanish, dutch

        /// What a document in this language calls the reverse charge and the
        /// rest, with the citation its own law uses.
        func notes(for treatment: VatTreatment) -> [String] {
            switch (self, treatment) {
            case (.german, .reverseCharge):
                return ["Steuerschuldnerschaft des Leistungsempfängers (§ 13b UStG)."]
            case (.german, .intraCommunitySupply):
                return ["Steuerfreie innergemeinschaftliche Lieferung (§ 4 Nr. 1b UStG)."]
            case (.german, .export):
                return ["Steuerfreie Ausfuhrlieferung (§ 4 Nr. 1a UStG)."]
            case (.german, .smallBusiness):
                return ["Gemäß § 19 UStG wird keine Umsatzsteuer berechnet."]
            case (.german, .exempt):
                return ["Steuerfrei."]

            case (.french, .reverseCharge):
                return ["Autoliquidation — TVA due par le preneur.",
                        "Article 283-2 du CGI ; article 196 de la directive 2006/112/CE."]
            case (.french, .intraCommunitySupply):
                return ["Livraison intracommunautaire exonérée.",
                        "Article 262 ter I du CGI ; article 138 de la directive 2006/112/CE."]
            case (.french, .export):
                return ["Exportation exonérée de TVA (article 262 I du CGI)."]
            case (.french, .smallBusiness):
                return ["TVA non applicable, article 293 B du CGI."]
            case (.french, .exempt):
                return ["Opération exonérée de TVA."]

            case (.italian, .reverseCharge):
                return ["Inversione contabile — IVA assolta dal committente.",
                        "Articolo 17 del DPR 633/72 ; articolo 196 della direttiva 2006/112/CE."]
            case (.italian, .intraCommunitySupply):
                return ["Cessione intracomunitaria non imponibile.",
                        "Articolo 41 del DL 331/93 ; articolo 138 della direttiva 2006/112/CE."]
            case (.italian, .export):
                return ["Operazione non imponibile (articolo 8 del DPR 633/72)."]
            case (.italian, .smallBusiness):
                return ["Operazione in regime forfettario, IVA non applicata."]
            case (.italian, .exempt):
                return ["Operazione esente IVA."]

            case (.spanish, .reverseCharge):
                return ["Inversión del sujeto pasivo — IVA a declarar por el destinatario.",
                        "Artículo 84 de la Ley 37/1992 ; artículo 196 de la Directiva 2006/112/CE."]
            case (.spanish, .intraCommunitySupply):
                return ["Entrega intracomunitaria exenta.",
                        "Artículo 25 de la Ley 37/1992 ; artículo 138 de la Directiva 2006/112/CE."]
            case (.spanish, .export):
                return ["Exportación exenta de IVA (artículo 21 de la Ley 37/1992)."]
            case (.spanish, .smallBusiness):
                return ["Operación sin IVA por régimen de franquicia."]
            case (.spanish, .exempt):
                return ["Operación exenta de IVA."]

            case (.dutch, .reverseCharge):
                return ["Btw verlegd — te voldoen door de afnemer.",
                        "Artikel 12 lid 3 Wet OB ; artikel 196 richtlijn 2006/112/EG."]
            case (.dutch, .intraCommunitySupply):
                return ["Intracommunautaire levering, 0% btw.",
                        "Tabel II post a6 Wet OB ; artikel 138 richtlijn 2006/112/EG."]
            case (.dutch, .export):
                return ["Uitvoer buiten de EU, 0% btw."]
            case (.dutch, .smallBusiness):
                return ["Geen btw in rekening gebracht — kleineondernemersregeling."]
            case (.dutch, .exempt):
                return ["Vrijgesteld van btw."]

            case (_, .standard):
                return []
            }
        }
    }

    /// The wording this treatment puts on the document.
    ///
    /// - Parameter also: A second language beside the English. The document
    ///   carries both, because the person reading it and the authority
    ///   checking it are often not the same person.
    public func notes(also language: Wording? = nil) -> [String] {
        let english: [String]

        switch self {
        case .standard:
            return []
        case .reverseCharge:
            english = [
                "Reverse charge: VAT to be accounted for by the recipient.",
                "Article 196, Council Directive 2006/112/EC.",
            ]
        case .intraCommunitySupply:
            english = [
                "Zero-rated intra-community supply.",
                "Article 138, Council Directive 2006/112/EC.",
            ]
        case .export:
            english = ["Zero-rated export outside the European Union."]
        case .smallBusiness:
            english = ["No VAT charged under the small-business scheme."]
        case .exempt:
            english = ["Exempt from VAT."]
        }

        guard let language else { return english }
        return english + language.notes(for: self)
    }

    /// The English wording, plus the German — as it was before other
    /// languages existed.
    public func notes(german: Bool) -> [String] {
        notes(also: german ? .german : nil)
    }

    /// Whether both parties' VAT numbers must appear.
    ///
    /// Mandatory for reverse charge and intra-community supply — the
    /// recipient's number evidences their status, and without it the zero
    /// rating is not supportable.
    public var requiresBothVatNumbers: Bool {
        self == .reverseCharge || self == .intraCommunitySupply
    }
}

// MARK: - Branding

/// How a document looks, separated from what it says, so one definition
/// styles everything you issue.
public struct Branding: Sendable, Equatable, Codable {

    public let name: String
    public let tagline: String

    /// Brand colour as hex. Black by default: a monochrome document is harder
    /// to date, prints correctly on any device, stays legible when
    /// photocopied, and never clashes with the recipient's own paperwork.
    public let accent: String

    /// An SVG `d` attribute for a vector mark.
    public let logoPath: String?

    /// The viewBox height that path was drawn in.
    public let logoBox: Double

    public let address: [String]

    /// Small print for the page foot.
    public let footnotes: [String]

    /// The typeface the documents are set in.
    ///
    /// A description of files rather than loaded fonts, so a branding profile
    /// stays something you can keep in version control beside your books. It
    /// is resolved by whoever renders — reading fonts off a disk is not work a
    /// value type should be doing.
    ///
    /// Left empty, the documents are set in Helvetica, which is the right
    /// default for paperwork: it prints on anything, photocopies, and is hard
    /// to date.
    public let typeface: TypefaceFiles?

    public init(
        name: String,
        tagline: String = "",
        accent: String = "#111111",
        logoPath: String? = nil,
        logoBox: Double = 100,
        address: [String] = [],
        footnotes: [String] = [],
        typeface: TypefaceFiles? = nil
    ) {
        self.name = name
        self.tagline = tagline
        self.accent = accent
        self.logoPath = logoPath
        self.logoBox = logoBox
        self.address = address
        self.footnotes = footnotes
        self.typeface = typeface
    }

    public var accentColor: Color { .hex(accent) }

    /// The brand family, loaded — or `nil` when no typeface is configured.
    ///
    /// `render` has no error channel, so a typeface whose files cannot be
    /// read falls back to Helvetica there, silently. The throwing callers —
    /// `save`, and anything producing a conforming file — go through this
    /// instead: a branding profile naming a font that is not on the disk is a
    /// mistake to report, not a styling preference to substitute.
    public func family() throws -> FontFamily? {
        try typeface.map { try $0.family() }
    }

    /// Secondary text.
    public var muted: Color { .grey(115) }

    /// Primary text. Not pure black — slightly lifted reads better in print
    /// and on screen, and is what most well-set documents use.
    public var ink: Color { .grey(32) }

    /// Faint fill for banded rows and panels.
    public var wash: Color { .grey(250) }

    /// Hairline for rules and borders.
    public var hairline: Color { .grey(214) }

    /// Whether this branding is effectively monochrome.
    public var isMonochrome: Bool {
        let colour = accentColor
        return colour.red == colour.green && colour.green == colour.blue
    }
}

// MARK: - Typeface files

/// The files making up a brand typeface.
///
/// Paths rather than bytes, and static TrueType instances rather than variable
/// ones — a variable font would embed as its default weight throughout, and
/// ``EmbeddedFont`` refuses one rather than let that happen quietly.
///
/// Only the weights given exist. A template asking for bold in a profile that
/// names one file gets that file, so a business with a single face still gets
/// its documents set in it.
public struct TypefaceFiles: Sendable, Equatable, Codable {

    public var name: String
    public var regular: String
    public var medium: String?
    public var semibold: String?
    public var bold: String?
    public var italic: String?

    public init(
        name: String = "",
        regular: String,
        medium: String? = nil,
        semibold: String? = nil,
        bold: String? = nil,
        italic: String? = nil
    ) {
        self.name = name
        self.regular = regular
        self.medium = medium
        self.semibold = semibold
        self.bold = bold
        self.italic = italic
    }

    /// Loads the family.
    public func family() throws -> FontFamily {
        var loaded = FontFamily(name: name.isEmpty ? "Brand" : name)

        func add(_ path: String?, _ weight: FontFamily.Weight, italic: Bool = false) throws {
            guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            loaded.add(try EmbeddedFont.load(url), weight: weight, italic: italic)
        }

        try add(regular, .regular)
        try add(medium, .medium)
        try add(semibold, .semibold)
        try add(bold, .bold)
        try add(italic, .regular, italic: true)

        return loaded
    }
}
