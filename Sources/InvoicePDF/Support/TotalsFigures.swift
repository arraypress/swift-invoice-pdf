//
//  TotalsFigures.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The arithmetic and formatting behind Totals, as pure functions. The one
//  rule that matters most is here by name: tax is taken on the total, not
//  per line — the two differ by a penny on some invoices, and the total is
//  the one the VAT directive describes. Living here, the rules are pinned
//  by tests that construct no Totals at all.
//

import Countries
import Foundation
import Money

/// What follows from lines, a rate and a currency.
enum TotalsFigures {

    /// The lines added up. Never nil-shaped: no lines is zero in the
    /// invoice's own currency, not an absence.
    static func net(of lines: [Totals.Line], in currency: Currency) -> Money {
        lines.map(\.amount).total(in: currency) ?? Money.zero(currency)
    }

    /// The tax, taken on the total rather than per line.
    static func tax(on net: Money, rate: Decimal, rounding: Money.RoundingMode) -> Money {
        net.percentage(rate, rounding: rounding)
    }

    /// The printed summary rows. A VAT row with nothing in it is a row
    /// too many, so a zero rate contributes none.
    static func rows(net: Money, tax: Money, rate: Decimal, in locale: Locale) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Subtotal", net.formatted(in: locale)),
        ]
        if rate != 0 {
            rows.append(("VAT at \(percentage(rate))%", tax.formatted(in: locale)))
        }
        return rows
    }

    /// The line items, ready for the template.
    static func items(from lines: [Totals.Line], in locale: Locale) -> [LineItem] {
        lines.map {
            LineItem(
                description: $0.description,
                amount: $0.amount.formatted(in: locale),
                quantity: String($0.quantity),
                unitPrice: $0.unitPrice.formatted(in: locale)
            )
        }
    }

    /// The VAT breakdown, at the one rate the lines share.
    static func vatLines(net: Money, tax: Money, rate: Decimal, in locale: Locale) -> [VatLine] {
        guard rate != 0 else { return [] }
        return [VatLine(rate: "\(percentage(rate))%",
                        net: net.formatted(in: locale),
                        vat: tax.formatted(in: locale))]
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
