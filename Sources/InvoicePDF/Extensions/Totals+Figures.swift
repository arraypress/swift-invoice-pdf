//
//  Totals+Figures.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Everything a Totals derives, each member one delegation into
//  TotalsFigures — no arithmetic lives here, so none can hide here.
//

import Countries
import Foundation
import Money

extension Totals {

    /// The lines added up.
    public var net: Money { TotalsFigures.net(of: lines, in: currency) }

    /// The tax, taken on the total rather than per line — the one the VAT
    /// directive describes.
    public var tax: Money { TotalsFigures.tax(on: net, rate: rate, rounding: rounding) }

    /// Net plus tax.
    public var gross: Money { net + tax }

    /// The rows a document prints, formatted from the same integers the XML
    /// carries — so the page and the record cannot disagree.
    public func rows(in locale: Locale = Totals.displayLocale) -> [(label: String, value: String)] {
        TotalsFigures.rows(net: net, tax: tax, rate: rate, in: locale)
    }

    /// The line items, ready for the template.
    public func items(in locale: Locale = Totals.displayLocale) -> [LineItem] {
        TotalsFigures.items(from: lines, in: locale)
    }

    /// The VAT breakdown, at the one rate these lines share.
    public func vatLines(in locale: Locale = Totals.displayLocale) -> [VatLine] {
        TotalsFigures.vatLines(net: net, tax: tax, rate: rate, in: locale)
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
        TotalsFigures.percentage(rate)
    }
}
