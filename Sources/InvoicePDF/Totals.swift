//
//  Totals.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Working the figures out, rather than being told them twice.
//
//  Every amount printed on an invoice is a string here, deliberately: how
//  money is written is a matter of currency and locale, and belongs wherever
//  the money lives. That worked until the e-invoice arrived, which needs the
//  same amounts as numbers — and left a caller writing each figure twice,
//  once for the page and once for the XML, with nothing checking that the two
//  agreed.
//
//  This is the other way round: give the lines as money, and both come out of
//  it. The strings on the page are formatted from the same integers the XML
//  carries, so they cannot disagree.
//

import Countries
import Foundation
import Money

/// Lines, a rate, and everything that follows from them.
public struct Totals: Sendable {

    /// One line's worth of money.
    public struct Line: Sendable {
        public let description: String
        public let quantity: Int
        public let unitPrice: Money

        public var amount: Money { unitPrice * quantity }

        public init(_ description: String, quantity: Int = 1, unitPrice: Money) {
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
        }
    }

    public let lines: [Line]

    /// The rate charged, as a percentage. Zero where none is.
    public let rate: Decimal

    /// How a fraction of a unit goes. Tax authorities usually specify half
    /// away from zero, which is the default.
    public let rounding: Money.RoundingMode

    public let currency: Currency

    public init(
        lines: [Line],
        rate: Decimal = 0,
        currency: Currency,
        rounding: Money.RoundingMode = .half
    ) {
        self.lines = lines
        self.rate = rate
        self.currency = currency
        self.rounding = rounding
    }

    // MARK: What follows

    /// The lines added up.
    public var net: Money {
        Money.total(lines.map(\.amount)) ?? Money.zero(currency)
    }

    /// The tax, taken on the total rather than per line.
    ///
    /// The two differ by a penny on some invoices, and this is the one the
    /// VAT directive describes: the rate applied to the taxable amount.
    public var tax: Money {
        net.percentage(rate, rounding: rounding)
    }

    /// Net plus tax.
    public var gross: Money { net + tax }

    /// The rows a document prints, formatted from the same integers the XML
    /// carries — so the page and the record cannot disagree.
    public func rows(in locale: Locale = .current) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Subtotal", net.formatted(in: locale)),
        ]
        if rate != 0 {
            rows.append(("VAT at \(Totals.percentage(rate))%", tax.formatted(in: locale)))
        }
        return rows
    }

    /// The line items, ready for the template.
    public func items(in locale: Locale = .current) -> [LineItem] {
        lines.map {
            LineItem(
                description: $0.description,
                amount: $0.amount.formatted(in: locale),
                quantity: String($0.quantity),
                unitPrice: $0.unitPrice.formatted(in: locale)
            )
        }
    }

    /// The VAT breakdown, at the one rate these lines share.
    public func vatLines(in locale: Locale = .current) -> [VatLine] {
        guard rate != 0 else { return [] }
        return [VatLine(rate: "\(Totals.percentage(rate))%",
                        net: net.formatted(in: locale),
                        vat: tax.formatted(in: locale))]
    }

    /// The figures an e-invoice needs, taken from the same arithmetic.
    ///
    /// The reason this type exists: nobody writes the numbers twice, so
    /// nothing can be written twice differently.
    public func facturX(
        profile: FacturX.Profile = .minimum,
        issued: Date,
        due: Date? = nil,
        buyerReference: String = ""
    ) -> FacturX {
        FacturX(
            profile: profile,
            currency: currency.code,
            issued: issued,
            due: due,
            totals: .init(net: net.decimal, tax: tax.decimal, gross: gross.decimal),
            taxRate: rate,
            buyerReference: buyerReference
        )
    }

    /// A rate as it is written: `20`, `19.5`, not `20.00`.
    static func percentage(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.usesGroupingSeparator = false
        return formatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }
}
