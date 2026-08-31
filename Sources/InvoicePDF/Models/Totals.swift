//
//  Totals.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Working the figures out, rather than being told them twice.
//
//  Every amount printed on an invoice is a string, deliberately: how money
//  is written is a matter of currency and locale. The e-invoice needs the
//  same amounts as numbers, and writing each figure twice — once for the
//  page, once for the XML — left nothing checking that the two agreed.
//
//  This type is the shape of that promise: lines, a rate, a currency. The
//  arithmetic and the formatted rows all derive from it in one place —
//  Support/TotalsFigures, reached through the Extensions file — so the page
//  and the record cannot disagree.
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

    /// The locale the formatted figures default to.
    ///
    /// Fixed rather than `Locale.current`, because two machines rendering
    /// the same invoice must produce the same bytes — a laptop set to de_DE
    /// and the CI that regenerates the examples cannot be allowed to
    /// disagree about where the thousands separator goes. Pass a locale to
    /// format for a particular reader; the default exists to be
    /// reproducible.
    public static let displayLocale = Locale(identifier: "en_US")

    /// - Precondition: Every line is in `currency`. An invoice is in one
    ///   currency — the code goes at the top of the page and once into the
    ///   XML, and there is nowhere for a second one to be written. A line in
    ///   another one is a mistake upstream, and taken this far it would
    ///   either stop the render halfway or, worse, produce a document
    ///   labelled in a currency its figures are not in.
    public init(
        lines: [Line],
        rate: Decimal = 0,
        currency: Currency,
        rounding: Money.RoundingMode = .half
    ) {
        if let stray = lines.first(where: { $0.unitPrice.currency != currency }) {
            preconditionFailure(
                "This invoice is in \(currency.code), but '\(stray.description)' is priced in "
                + "\(stray.unitPrice.currency.code). Convert it before it gets here — that needs "
                + "a rate and a date, which an invoice records and this does not have."
            )
        }

        self.lines = lines
        self.rate = rate
        self.currency = currency
        self.rounding = rounding
    }
}
