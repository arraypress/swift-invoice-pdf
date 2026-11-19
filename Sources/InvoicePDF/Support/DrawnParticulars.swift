//
//  DrawnParticulars.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Whether a party's particulars reached the page. Pure functions of the
//  drawn text, so the matching rule is pinned without rendering anything.
//
//  The check this exists for was missing for a long time: the supplier's
//  name, address and VAT number were never drawn on an invoice, and every
//  compliance check passed, because they all asked whether the fields were
//  set rather than whether they were printed.
//

import Foundation

/// A party's particulars, checked against what was drawn.
enum DrawnParticulars {

    /// Everything drawn, as one string with the whitespace taken out.
    ///
    /// Whitespace goes because a line wrapped to fit its column is still on
    /// the page — and a word too wide for the column is broken mid-word, so
    /// rejoining the pieces with a space would not give the original back.
    static func page(_ drawn: [String]) -> String {
        drawn.joined().filter { !$0.isWhitespace }
    }

    /// Whether `text` appears on a ``page(_:)``. Blank text is trivially there.
    static func shows(_ text: String, on page: String) -> Bool {
        let squeezed = text.filter { !$0.isWhitespace }
        return squeezed.isEmpty || page.contains(squeezed)
    }

    /// The particulars of one party that were set and did not reach the page.
    ///
    /// Named by the party rather than by a role: on a self-billed invoice or
    /// a purchase order the issuer is the customer, and a warning about "the
    /// supplier" would send the reader to the wrong block.
    static func missing(
        name: String,
        address: [String],
        taxID: String,
        registration: String,
        on page: String
    ) -> [String] {
        let who = name.trimmingCharacters(in: .whitespaces).isEmpty ? "a party" : name
        var out: [String] = []

        if !shows(name, on: page) {
            out.append("The name \"\(name)\" did not reach the page.")
        }
        for line in address where !shows(line, on: page) {
            out.append("The address line \"\(line)\" of \(who) did not reach the page.")
        }
        if !shows(taxID, on: page) {
            out.append("The VAT or tax number \"\(taxID)\" of \(who) did not reach the page.")
        }
        if !shows(registration, on: page) {
            out.append("The registration \"\(registration)\" of \(who) did not reach the page.")
        }
        return out
    }
}
