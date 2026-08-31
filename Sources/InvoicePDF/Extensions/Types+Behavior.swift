//
//  Types+Behavior.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The derived facts of the shared value types, each one a delegation into
//  Support — the models keep their shape, the rules keep one home.
//

import Foundation
import TextPDF

extension Party {

    /// The address block, with a link where a line has somewhere to go.
    public func linkedLines(vatLabel: String = "VAT") -> [(text: String, url: String)] {
        PartyLines.linked(address: address, email: email, taxID: taxID, vatLabel: vatLabel)
    }

    /// The address block, one string per line.
    public func lines(vatLabel: String = "VAT") -> [String] {
        PartyLines.plain(address: address, email: email, taxID: taxID, vatLabel: vatLabel)
    }
}

extension VatTreatment {

    /// The wording this treatment puts on the document.
    ///
    /// - Parameter also: A second language beside the English. The document
    ///   carries both, because the person reading it and the authority
    ///   checking it are often not the same person.
    public func notes(also language: Wording? = nil) -> [String] {
        if self == .standard { return [] }
        let english = VatWording.english(self)
        guard let language else { return english }
        return english + VatWording.notes(for: self, in: language)
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

extension VatTreatment.Wording {

    /// What a document in this language calls the treatment.
    func notes(for treatment: VatTreatment) -> [String] {
        VatWording.notes(for: treatment, in: self)
    }
}

extension TypefaceFiles {

    /// Loads the family.
    public func family() throws -> FontFamily {
        try TypefaceLoading.family(from: self)
    }
}
