//
//  PartyLines.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  A party's address block assembled, plain or linked. Pure functions of
//  the fields, so the skip-blank and mailto-trimming rules are pinned
//  without a Party in sight.
//

import Foundation

/// The address block a document prints for a party.
enum PartyLines {

    /// The block with a link where a line has somewhere to go. An invoice
    /// is read from a screen at least as often as from paper, and the
    /// supplier's email address is the one thing on it a recipient
    /// actually needs to act on when something is wrong.
    static func linked(address: [String], email: String, taxID: String, vatLabel: String) -> [(text: String, url: String)] {
        var out = address.map { (text: $0, url: "") }
        if !email.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((email, "mailto:\(email.trimmingCharacters(in: .whitespaces))"))
        }
        if !taxID.isEmpty { out.append(("\(vatLabel) \(taxID)", "")) }
        return out.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The block as plain strings, blank lines dropped.
    static func plain(address: [String], email: String, taxID: String, vatLabel: String) -> [String] {
        var lines = address
        if !email.isEmpty { lines.append(email) }
        if !taxID.isEmpty { lines.append("\(vatLabel) \(taxID)") }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
