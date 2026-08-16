//
//  Currency.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  How many decimal places a currency has.
//
//  Two is the common answer and the wrong default to bake in. The yen has no
//  minor unit at all — ¥1000 is written 1000, and 1000.00 says its author did
//  not know that. The Kuwaiti dinar has three, and rounding one to two places
//  does not look wrong: it silently drops a fils off a tax document, which is
//  money going missing rather than a formatting quibble.
//
//  ISO 4217 calls this the minor unit. The table is short because almost
//  everything is two: what is listed here is everything that is not.
//

import Foundation

/// The precision a currency is written to.
enum Currency {

    /// Currencies with no minor unit — the amount is a whole number.
    private static let none: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
        "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    ]

    /// Currencies written to three places.
    private static let three: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND",
    ]

    /// Currencies written to four.
    private static let four: Set<String> = ["CLF", "UYW"]

    /// How many decimal places `code` is written to.
    ///
    /// Two for anything unlisted, which is right for every ordinary currency
    /// and wrong quietly for the two dozen that are not — hence the table.
    static func places(_ code: String) -> Int {
        let upper = code.uppercased()
        if none.contains(upper) { return 0 }
        if three.contains(upper) { return 3 }
        if four.contains(upper) { return 4 }
        return 2
    }

    /// The amount as the currency writes it: rounded to its own precision,
    /// a full stop, no separators.
    static func amount(_ value: Decimal, in code: String) -> String {
        let places = places(code)

        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, places, .plain)

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.usesGroupingSeparator = false

        return formatter.string(from: rounded as NSDecimalNumber) ?? "0"
    }

    /// The smallest amount the currency can express: 1 for the yen, 0.001 for
    /// the dinar, 0.01 for most.
    static func smallestUnit(_ code: String) -> Decimal {
        Decimal(sign: .plus, exponent: -places(code), significand: 1)
    }

    /// Where a figure is finer than the currency can express.
    ///
    /// Refused rather than rounded away: ¥1000.50 is not a yen amount, and
    /// deciding on somebody's behalf whether that is 1000 or 1001 is deciding
    /// what their invoice says.
    static func tooPrecise(_ value: Decimal, in code: String, called name: String) -> String? {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, places(code), .plain)

        // Meaningfully finer, not merely different in the sixteenth digit.
        // Swift's Decimal takes a float literal through Double, so a caller
        // who writes 1234.56 gets 1234.5599999999997952 — and refusing that
        // would be refusing the ordinary way of writing an amount. A
        // hundredth of the smallest unit separates that noise from ¥1000.50,
        // which is a real half-yen nobody can pay.
        let noise = smallestUnit(code) / 100
        guard abs(rounded - value) > noise else { return nil }

        let upper = code.uppercased()
        let unit = places(upper)
        return unit == 0
            ? "\(name) is \(value), and \(upper) has no minor unit — it is written as a whole number."
            : "\(name) is \(value), which is finer than \(upper)'s \(unit) decimal places."
    }
}
