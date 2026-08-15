//
//  PaymentCode.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The square somebody points a phone at.
//
//  A payment code turns "read these sixteen digits off the page and type them
//  into your banking app" into one scan, and it is where the mistakes come
//  from otherwise — a transposed IBAN digit is a payment that bounces a week
//  later, and a missing reference is a payment nobody can match to an invoice.
//
//  Two of these are worth knowing by name. The **EPC** code is what a European
//  banking app scans for a SEPA credit transfer; the **Swiss QR-bill** replaced
//  the payment slip in Switzerland and is mandatory there. Anything else — a
//  link to a payment page, a card processor's URL — is just a string, so this
//  carries the payload it is given rather than pretending to know them all.
//

import Foundation

/// A code printed on the document, and the words under it.
public struct PaymentCode: Sendable, Equatable {

    /// What the scanner reads. A URL, an EPC payload, whatever the recipient's
    /// app expects.
    public let payload: String

    /// The line under the code, so somebody who cannot scan it knows what it
    /// was for.
    public let caption: String

    public init(_ payload: String, caption: String = "Scan to pay") {
        self.payload = payload
        self.caption = caption
    }

    // MARK: The ones with a specification

    /// A SEPA credit transfer, as European banking apps read it.
    ///
    /// EPC069-12. The rules that bite are enforced rather than documented: the
    /// amount is euro only, the name is capped at 70 characters and the
    /// reference at 140, and an app given more than that shows an error rather
    /// than a payment.
    ///
    /// - Parameters:
    ///   - amount: In euro. `nil` leaves it for the payer to type, which is
    ///     what an open invoice with a part payment against it wants.
    ///   - reference: What the payer sees and what you will match the payment
    ///     against. The invoice number, in practice.
    /// - Returns: `nil` where the details cannot make a valid code.
    public static func epc(
        beneficiary: String,
        iban: String,
        amount: Decimal? = nil,
        bic: String = "",
        reference: String = "",
        caption: String = "Scan to pay"
    ) -> PaymentCode? {
        let name = beneficiary.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = iban.replacingOccurrences(of: " ", with: "").uppercased()
        let note = reference.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, name.count <= 70,
              account.count >= 15, account.count <= 34,
              note.count <= 140
        else { return nil }

        var money = ""
        if let amount {
            guard amount > 0, amount < 1_000_000_000 else { return nil }

            var rounded = Decimal()
            var input = amount
            NSDecimalRound(&rounded, &input, 2, .plain)

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.usesGroupingSeparator = false
            guard let figure = formatter.string(from: rounded as NSDecimalNumber) else { return nil }
            money = "EUR\(figure)"
        }

        // The order is the specification's, and the empty lines are load
        // bearing — an app counts them to find the fields it wants.
        let payload = [
            "BCD",          // service tag
            "002",          // version
            "1",            // UTF-8
            "SCT",          // SEPA credit transfer
            bic.trimmingCharacters(in: .whitespaces),
            name,
            account,
            money,
            "",             // purpose code
            "",             // structured reference
            note,           // unstructured reference
        ].joined(separator: "\n")

        return PaymentCode(payload, caption: caption)
    }
}
