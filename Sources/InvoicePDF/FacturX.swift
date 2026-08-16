//
//  FacturX.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The machine-readable half of an invoice.
//
//  Germany's e-invoicing mandate is phasing in, France's follows, Italy's has
//  been running for years, and all of them want the same thing: an invoice a
//  system can read without looking at the picture. Factur-X — ZUGFeRD in
//  Germany, the same specification — says how. One PDF/A-3, carrying the
//  invoice as XML. The page is what a person reads; the attachment is what
//  the buyer's ledger reads; neither is a rendering of the other.
//
//  ## Why the figures are given rather than taken
//
//  Every amount on an ``Invoice`` is a string, deliberately: formatting money
//  means knowing a currency's decimal exponent, its separators and where its
//  symbol goes, and that belongs where the money lives. The XML wants the
//  opposite — a decimal a machine can add up, and a currency code.
//
//  Reading "£1.234,56" back into a number means guessing whether the comma is
//  a decimal point, and a guess that is wrong by a factor of a thousand on a
//  tax return is not a guess worth making. So the figures come from the
//  caller, who already had them as numbers before formatting them for the
//  page.
//

import Countries
import Foundation
import Money
import TextPDF

/// The invoice, as the data a system reads.
public struct FacturX: Sendable, Equatable {

    /// How much of the specification the XML fills in.
    public enum Profile: String, Sendable, CaseIterable {

        /// Header, parties, totals and tax. Accepted in France as a
        /// *données d'en-tête* document and enough to satisfy the ordinary
        /// case, where the page carries the detail.
        case minimum = "urn:factur-x.eu:1p0:minimum"

        /// The same, with the tax breakdown and payment terms — everything a
        /// ledger needs except the line items.
        case basicWithoutLines = "urn:factur-x.eu:1p0:basicwl"

        /// What the profile is called in the specification, for a message
        /// that has to name it.
        public var name: String {
            switch self {
            case .minimum: return "Minimum"
            case .basicWithoutLines: return "Basic WL"
            }
        }
    }

    /// What the whole document is worth, in figures.
    ///
    /// Four totals rather than one, because a tax authority checks that they
    /// agree: net plus tax is gross, and gross less anything already paid is
    /// what is due.
    public struct Totals: Sendable, Equatable {

        /// The sum of the lines, before tax.
        public var net: Decimal

        /// The tax charged. Zero under reverse charge — the liability moves,
        /// it does not vanish, and the XML says so through the category code.
        public var tax: Decimal

        /// Net plus tax.
        public var gross: Decimal

        /// What remains payable, after anything already paid.
        public var due: Decimal

        /// - Note: Swift takes a float literal to `Decimal` through `Double`,
        ///   so `1234.56` arrives as 1234.5599999999997952. It rounds and
        ///   prints correctly, and the checks here allow for it — but
        ///   `Decimal(string: "1234.56")` is exact, and exact is what money
        ///   deserves in code that adds it up.
        public init(net: Decimal, tax: Decimal, gross: Decimal, due: Decimal? = nil) {
            self.net = net
            self.tax = tax
            self.gross = gross
            self.due = due ?? gross
        }

        /// Where these figures do not agree with each other.
        ///
        /// A total that does not add up is the most embarrassing thing an
        /// invoice can carry, and the one a customer notices first. It is
        /// also the only arithmetic that can be checked here: every amount
        /// printed on the page is a string, deliberately, because formatting
        /// money means knowing a currency's conventions — but these four
        /// numbers were given as numbers, and net plus tax is gross wherever
        /// you are.
        public func disagreements(currency: String = "") -> [String] {
            var found: [String] = []

            let code = currency.isEmpty ? "XXX" : currency
            let money = Currency(code)

            // Before anything is compared, that all four are amounts at all.
            // A figure past what money can hold — or one that is not a number
            // — has to be caught here rather than further down, because
            // everything after this point formats it, and formatting an
            // impossible number is where one silently becomes a possible and
            // completely different one.
            for (name, value) in [("net", net), ("tax", tax), ("gross", gross), ("due", due)]
            where Money(exactly: value, in: money) == nil {
                found.append(
                    "The \(name) is not an amount that can be written: \(value). "
                        + "Money runs to about 9×10^18 of a currency's smallest unit."
                )
            }
            guard found.isEmpty else { return found }

            func show(_ value: Decimal) -> String {
                let figure = Money(value, in: Currency(code)).decimalString
                return currency.isEmpty ? figure : "\(currency) \(figure)"
            }

            // Compared as the document prints them, because that is what a
            // customer adds up. A tax of 20% on 1234.56 is 246.912 and lands
            // on the page as 246.91; checking the unrounded figures would
            // report a disagreement nobody can see.
            func rounded(_ value: Decimal) -> Decimal {
                Money(value, in: money).decimal
            }

            // One of the currency's own smallest units either way is
            // rounding — a rate applied per line legitimately lands there.
            // A penny of tolerance would be a hundred times too loose for
            // the yen and ten times too tight for the dinar.
            let unit = Decimal(1) / Decimal(money.unitsPerMajor)
            let tolerance = unit + unit / 10

            let net = rounded(self.net), tax = rounded(self.tax)
            let gross = rounded(self.gross), due = rounded(self.due)

            let sum = net + tax
            if abs(sum - gross) > tolerance {
                found.append(
                    "The total does not add up: \(show(net)) plus \(show(tax)) is \(show(sum)), "
                        + "and the gross says \(show(gross))."
                )
            }

            if due > gross + tolerance {
                found.append(
                    "More is payable than the invoice is for: \(show(due)) against \(show(gross))."
                )
            }

            if net < 0 || tax < 0 || gross < 0 {
                found.append("An amount is negative. A refund is a credit note, not a minus sign.")
            }

            return found
        }
    }

    public var profile: Profile

    /// ISO 4217, three letters: GBP, EUR, CHF.
    public var currency: String

    /// The date the invoice was issued, as `yyyy-MM-dd`.
    ///
    /// Not the string on the page: "31 July 2026" is for a person, and a
    /// system reading it has to guess a locale to know which number is the
    /// month.
    public var issued: Date

    /// When payment is due, where the document says so.
    public var due: Date?

    public var totals: Totals

    /// The rate charged, as a percentage — 20 for 20%. Zero where none is.
    public var taxRate: Decimal

    /// The buyer's own reference, which several tax authorities require the
    /// invoice to quote. France requires it for public bodies.
    public var buyerReference: String

    /// When the goods or services actually arrived.
    ///
    /// Optional on an ordinary invoice and required on an intra-community
    /// supply, where the zero rate depends on the goods having crossed a
    /// border on a date — rule BR-IC-11.
    public var delivered: Date?

    /// Where they arrived, if that is not where the customer is.
    ///
    /// Defaults to the customer's own country, which is where a delivery
    /// goes unless somebody says otherwise. An intra-community supply must
    /// state one — rule BR-IC-12 — because the country it went to is the
    /// whole basis of the zero rate.
    public var deliveredTo: Country?

    public init(
        profile: Profile = .minimum,
        currency: String,
        issued: Date,
        due: Date? = nil,
        totals: Totals,
        taxRate: Decimal = 0,
        buyerReference: String = "",
        delivered: Date? = nil,
        deliveredTo: Country? = nil
    ) {
        self.profile = profile
        self.currency = currency
        self.issued = issued
        self.due = due
        self.totals = totals
        self.taxRate = taxRate
        self.buyerReference = buyerReference
        self.delivered = delivered
        self.deliveredTo = deliveredTo
    }
}

// MARK: - Making the XML

extension Invoice {

    /// What goes wrong before an invoice can be sent as an e-invoice.
    public enum FacturXError: Error, Equatable, CustomStringConvertible {

        /// Only some kinds of document are invoices. A delivery note is not
        /// one, and neither is a quote.
        case notAnInvoice(DocumentKind)

        /// The particulars an e-invoice must carry, which are stricter than
        /// the ones a printed invoice must.
        case missing([String])

        public var description: String {
            switch self {
            case .notAnInvoice(let kind):
                let sentence = "A \(kind.title.lowercased()) is not an invoice, so it has no e-invoice form."
                return sentence + " Factur-X covers invoices, credit and debit notes,"
                    + " proformas and self-billed invoices."
            case .missing(let fields):
                let joined = fields.joined(separator: " ")
                return "This cannot be sent as an e-invoice: " + joined
            }
        }
    }

    /// The invoice as Factur-X XML.
    ///
    /// - Throws: ``FacturXError`` when the document is not an invoice, or is
    ///   missing something the standard requires. Refusing beats attaching XML
    ///   a buyer's system will reject, because the rejection arrives days
    ///   later and against your name.
    public func facturX(_ details: FacturX) throws -> Data {
        guard let typeCode = kind.facturXTypeCode else { throw FacturXError.notAnInvoice(kind) }

        var missing: [String] = []
        if number.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("It has no number.") }
        if from.name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("The supplier has no name.") }
        if to.name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("The customer has no name.") }
        if from.taxID.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("The supplier has no VAT or tax number, which an e-invoice must carry.")
        }
        if details.currency.count != 3 {
            missing.append("\"\(details.currency)\" is not an ISO 4217 currency code.")
        }
        // EN 16931 caps every document-level amount at two decimals — rules
        // BR-DEC-09 through BR-DEC-20 — whatever the currency's own minor
        // unit is. So the standard cannot express an invoice in dinars: a
        // fils is a third decimal, and writing the figure to two loses it.
        //
        // Refused rather than rounded. Rounding would make the XML disagree
        // with the page by up to half a fils, which is the exact thing the
        // figures are worked out once to prevent, and the disagreement would
        // be invisible until somebody reconciled the two.
        let money = Currency(details.currency)
        if money.decimals > 2 {
            missing.append(
                "An e-invoice cannot be written in \(money.code). It has \(money.decimals) "
                + "decimal places and EN 16931 allows two (BR-DEC-09 to BR-DEC-20), so the "
                + "amounts would have to lose a digit the currency actually uses."
            )
        }
        if vat == .reverseCharge, to.taxID.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("Reverse charge needs the customer's VAT number.")
        }
        // BR-09. A validator rejects the document outright without it, and
        // the rejection arrives days later — so it is refused here, where the
        // fix is one field.
        if from.country == nil {
            missing.append(
                "The supplier has no country. EN 16931 requires one in the address "
                + "(BR-09) — set Party(country:), which is not printed."
            )
        }
        // BR-11, which applies from Basic WL up: that profile carries the
        // buyer's address, and an address there needs its country too.
        if details.profile != .minimum, to.country == nil {
            missing.append(
                "The customer has no country. The \(details.profile.name) profile carries their "
                + "address, and EN 16931 requires a country in it (BR-11)."
            )
        }
        // BR-IC-11 and BR-IC-12. The zero rate on an intra-community supply
        // rests on the goods having crossed a border, so the document has to
        // say which border and on what day. Without either, the document
        // claims a zero rate it does not evidence.
        if vat == .intraCommunitySupply, details.profile != .minimum {
            if details.delivered == nil {
                missing.append(
                    "An intra-community supply needs the date the goods arrived "
                    + "(BR-IC-11) — set FacturX(delivered:)."
                )
            }
            if details.deliveredTo ?? to.country == nil {
                missing.append(
                    "An intra-community supply needs the country the goods went to "
                    + "(BR-IC-12) — set FacturX(deliveredTo:), or the customer's country."
                )
            }
        }
        // A document whose own totals disagree is one a buyer's system
        // rejects — and the rejection arrives days later, against your name.
        missing += details.totals.disagreements(currency: details.currency)

        guard missing.isEmpty else { throw FacturXError.missing(missing) }

        return Data(FacturXWriter.xml(self, details: details, typeCode: typeCode).utf8)
    }

    /// Renders the document and attaches its own XML, as a conforming file.
    ///
    /// The single call that makes an e-invoice: the page a person reads and
    /// the record a system reads, in one file that claims PDF/A-3 and means it.
    ///
    /// - Parameter family: The typeface to set it in. Required, and not for
    ///   decoration — PDF/A carries every font it uses, and the base-14 faces
    ///   belong to the reader.
    public func facturXDocument(
        _ details: FacturX,
        in family: FontFamily,
        fallback: EmbeddedFont? = nil,
        creationDate: Date = Date()
    ) throws -> Data {
        let xml = try facturX(details)
        let document = render(in: family, fallback: fallback)

        document.attach(
            xml,
            name: "factur-x.xml",
            mimeType: "text/xml",
            description: "Factur-X invoice",
            relationship: .alternative,
            modified: details.issued
        )

        return document.render(
            metadata: [
                "Title": "\(kind.title) \(number)",
                "Author": from.name,
                "Subject": "\(kind.title) \(number) — \(to.name)",
            ],
            creationDate: creationDate,
            standard: .pdfA3b
        )
    }
}

// MARK: - The document type codes

extension DocumentKind {

    /// UNTDID 1001, which is how the XML says what kind of document this is.
    ///
    /// `nil` for the kinds that are not invoices. A delivery note and a
    /// purchase order are real documents with their own message types; giving
    /// them an invoice code to make the file generate would put a document
    /// into somebody's ledger as a bill.
    public var facturXTypeCode: String? {
        switch self {
        case .invoice: return "380"
        case .creditNote: return "381"
        case .debitNote: return "383"
        case .proforma: return "325"
        case .selfBilling: return "389"
        case .quote, .receipt, .reminder, .remittance,
             .deliveryNote, .purchaseOrder, .orderConfirmation:
            return nil
        }
    }
}

// MARK: - Cross Industry Invoice

/// Writes the CII XML the standard specifies.
enum FacturXWriter {

    static func xml(_ invoice: Invoice, details: FacturX, typeCode: String) -> String {
        let date = DateFormatter()
        date.dateFormat = "yyyyMMdd"
        date.timeZone = TimeZone(identifier: "UTC")
        date.locale = Locale(identifier: "en_US_POSIX")

        let currency = details.currency.uppercased()
        let category = invoice.vat.facturXCategory

        var trade = """
            <ram:ApplicableHeaderTradeAgreement>
              <ram:BuyerReference>\(escaped(details.buyerReference))</ram:BuyerReference>
              <ram:SellerTradeParty>
                <ram:Name>\(escaped(invoice.from.name))</ram:Name>
        \(address(invoice.from))\
                <ram:SpecifiedTaxRegistration>
                  <ram:ID schemeID="VA">\(escaped(invoice.from.taxID))</ram:ID>
                </ram:SpecifiedTaxRegistration>
              </ram:SellerTradeParty>
              <ram:BuyerTradeParty>
                <ram:Name>\(escaped(invoice.to.name))</ram:Name>
        \(details.profile == .minimum ? "" : address(invoice.to))\
        \(details.profile == .minimum || invoice.to.taxID.isEmpty ? "" : """
                <ram:SpecifiedTaxRegistration>
                  <ram:ID schemeID="VA">\(escaped(invoice.to.taxID))</ram:ID>
                </ram:SpecifiedTaxRegistration>

        """)\
              </ram:BuyerTradeParty>
            </ram:ApplicableHeaderTradeAgreement>
        """

        if !invoice.reference.isEmpty {
            trade = trade.replacingOccurrences(
                of: "</ram:ApplicableHeaderTradeAgreement>",
                with: """
                      <ram:BuyerOrderReferencedDocument>
                        <ram:IssuerAssignedID>\(escaped(invoice.reference))</ram:IssuerAssignedID>
                      </ram:BuyerOrderReferencedDocument>
                    </ram:ApplicableHeaderTradeAgreement>
                """
            )
        }

        // The tax block. Under reverse charge the amount is zero and the
        // category code carries the reason — a system that sees "0" with no
        // reason files it as a mistake.
        //
        // The order of these is not a style: CII declares a sequence, so a
        // reader hits the first element out of place and rejects the file.
        // ExemptionReason is third, before BasisAmount, however naturally it
        // reads next to the category code it explains.
        let tax = """
              <ram:ApplicableTradeTax>
                <ram:CalculatedAmount>\(amount(details.totals.tax, in: currency))</ram:CalculatedAmount>
                <ram:TypeCode>VAT</ram:TypeCode>
        \(category.reason.isEmpty ? "" : "        <ram:ExemptionReason>\(escaped(category.reason))</ram:ExemptionReason>\n")\
                <ram:BasisAmount>\(amount(details.totals.net, in: currency))</ram:BasisAmount>
                <ram:CategoryCode>\(category.code)</ram:CategoryCode>
                <ram:RateApplicablePercent>\(Money(details.taxRate, in: Currency("XXX")).decimalString)</ram:RateApplicablePercent>
              </ram:ApplicableTradeTax>
        """

        let dueDate = details.due.map { """
              <ram:SpecifiedTradePaymentTerms>
                <ram:DueDateDateTime>
                  <udt:DateTimeString format="102">\(date.string(from: $0))</udt:DateTimeString>
                </ram:DueDateDateTime>
              </ram:SpecifiedTradePaymentTerms>
        """ } ?? ""

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsm:CrossIndustryInvoice
          xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
          xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
          xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
          <rsm:ExchangedDocumentContext>
            <ram:GuidelineSpecifiedDocumentContextParameter>
              <ram:ID>\(details.profile.rawValue)</ram:ID>
            </ram:GuidelineSpecifiedDocumentContextParameter>
          </rsm:ExchangedDocumentContext>
          <rsm:ExchangedDocument>
            <ram:ID>\(escaped(invoice.number))</ram:ID>
            <ram:TypeCode>\(typeCode)</ram:TypeCode>
            <ram:IssueDateTime>
              <udt:DateTimeString format="102">\(date.string(from: details.issued))</udt:DateTimeString>
            </ram:IssueDateTime>
          </rsm:ExchangedDocument>
          <rsm:SupplyChainTradeTransaction>
        \(indented(trade))\
        \(delivery(invoice, details: details))\
            <ram:ApplicableHeaderTradeSettlement>
              <ram:InvoiceCurrencyCode>\(escaped(currency))</ram:InvoiceCurrencyCode>
        \(tax)
        \(dueDate)\
              <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
                <ram:LineTotalAmount>\(amount(details.totals.net, in: currency))</ram:LineTotalAmount>
                <ram:TaxBasisTotalAmount>\(amount(details.totals.net, in: currency))</ram:TaxBasisTotalAmount>
                <ram:TaxTotalAmount currencyID="\(escaped(currency))">\(amount(details.totals.tax, in: currency))</ram:TaxTotalAmount>
                <ram:GrandTotalAmount>\(amount(details.totals.gross, in: currency))</ram:GrandTotalAmount>
                <ram:DuePayableAmount>\(amount(details.totals.due, in: currency))</ram:DuePayableAmount>
              </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            </ram:ApplicableHeaderTradeSettlement>
          </rsm:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
        """
    }

    // MARK: Pieces

    /// Where the goods went and when.
    ///
    /// Empty on an ordinary invoice, because nothing here is required and an
    /// empty element is what the Minimum profile expects. An intra-community
    /// supply is different: the zero rate rests on the goods having crossed a
    /// border on a date, so BR-IC-11 and BR-IC-12 require both, and without
    /// them a validator rejects the document.
    ///
    /// The order is CII's, not this file's: ShipToTradeParty comes before the
    /// delivery event, and a reader stops at the first element out of place.
    /// `yyyyMMdd`, which is what format 102 means.
    private static var compactDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }

    private static func delivery(_ invoice: Invoice, details: FacturX) -> String {
        // The Minimum profile has no delivery group at all.
        guard details.profile != .minimum else {
            return "    <ram:ApplicableHeaderTradeDelivery/>"
        }

        let country = details.deliveredTo ?? invoice.to.country
        var out = "    <ram:ApplicableHeaderTradeDelivery>\n"

        if let country {
            out += """
                  <ram:ShipToTradeParty>
                    <ram:PostalTradeAddress>
                      <ram:CountryID>\(escaped(country.code))</ram:CountryID>
                    </ram:PostalTradeAddress>
                  </ram:ShipToTradeParty>

            """
        }
        if let delivered = details.delivered {
            out += """
                  <ram:ActualDeliverySupplyChainEvent>
                    <ram:OccurrenceDateTime>
                      <udt:DateTimeString format="102">\(compactDate.string(from: delivered))</udt:DateTimeString>
                    </ram:OccurrenceDateTime>
                  </ram:ActualDeliverySupplyChainEvent>

            """
        }
        out += "    </ram:ApplicableHeaderTradeDelivery>"
        return out
    }

    /// The party's address, as the standard wants it.
    ///
    /// The country is the one part of an address the standard insists on —
    /// `CountryID` is required, once, and a document without it fails BR-09
    /// at any validator. It comes from ``Party/country`` rather than from the
    /// last line of the address: the previous version took a two-letter final
    /// line as the country, which found nothing in "London WC2H 9JQ" and
    /// would have found Canada in "Sacramento, CA".
    private static func address(_ party: Party) -> String {
        guard !party.address.isEmpty || party.country != nil else { return "" }

        let lines = party.address
        var out = "        <ram:PostalTradeAddress>\n"
        if let first = lines.first {
            out += "          <ram:LineOne>\(escaped(first))</ram:LineOne>\n"
        }
        if lines.count > 1 {
            out += "          <ram:LineTwo>\(escaped(lines[1]))</ram:LineTwo>\n"
        }
        if let country = party.country {
            out += "          <ram:CountryID>\(escaped(country.code))</ram:CountryID>\n"
        }
        out += "        </ram:PostalTradeAddress>\n"
        return out
    }

    /// The amount as its own currency writes it: the yen to no places, the
    /// dinar to three, everything ordinary to two.
    ///
    /// Through `Money`, which counts in the currency's smallest unit — so the
    /// figure written here is the same integer the arithmetic used.
    ///
    /// The figures reaching this point have already been through
    /// ``FacturX/Totals/disagreements(currency:)``, which refuses anything
    /// too large to be written before any XML is built.
    private static func amount(_ value: Decimal, in code: String) -> String {
        Money(value, in: Currency(code)).decimalString
    }

    private static func indented(_ block: String) -> String {
        block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "  \($0)" }
            .joined(separator: "\n") + "\n"
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Tax categories

extension VatTreatment {

    /// The UNTDID 5305 category, and why, where the standard wants a reason.
    var facturXCategory: (code: String, reason: String) {
        switch self {
        case .standard: return ("S", "")
        case .reverseCharge: return ("AE", "Reverse charge")
        case .intraCommunitySupply: return ("K", "Intra-Community supply")
        case .export: return ("G", "Export outside the EU")
        case .smallBusiness: return ("E", "Small business exemption")
        case .exempt: return ("E", "Exempt")
        }
    }
}
