//
//  VatWording.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The words that make a zero-rated document evidence. Moved out of the
//  model so the table is a pure function of (treatment, language), pinned
//  by tests to the exact strings — a wrong phrase in a language you do not
//  read is worse than an English one you do.
//
//  **Not legal advice.** These are the standard formulations and the
//  articles they cite, which are published and formulaic.
//

import Foundation

/// The statutory wordings, by treatment and language.
enum VatWording {

    /// The English wording for a treatment. Standard-rated documents say
    /// nothing — the VAT row already says it.
    static func english(_ treatment: VatTreatment) -> [String] {
        switch treatment {
        case .standard:
            return []
        case .reverseCharge:
            return [
                "Reverse charge: VAT to be accounted for by the recipient.",
                "Article 196, Council Directive 2006/112/EC.",
            ]
        case .intraCommunitySupply:
            return [
                "Zero-rated intra-community supply.",
                "Article 138, Council Directive 2006/112/EC.",
            ]
        case .export:
            return ["Zero-rated export outside the European Union."]
        case .smallBusiness:
            return ["No VAT charged under the small-business scheme."]
        case .exempt:
            return ["Exempt from VAT."]
        }
    }

    /// What a document in this language calls the reverse charge and the
    /// rest, with the citation its own law uses.
    static func notes(for treatment: VatTreatment, in language: VatTreatment.Wording) -> [String] {
            switch (language, treatment) {
        case (.german, .reverseCharge):
            return ["Steuerschuldnerschaft des Leistungsempfängers (§ 13b UStG)."]
        case (.german, .intraCommunitySupply):
            return ["Steuerfreie innergemeinschaftliche Lieferung (§ 4 Nr. 1b UStG)."]
        case (.german, .export):
            return ["Steuerfreie Ausfuhrlieferung (§ 4 Nr. 1a UStG)."]
        case (.german, .smallBusiness):
            return ["Gemäß § 19 UStG wird keine Umsatzsteuer berechnet."]
        case (.german, .exempt):
            return ["Steuerfrei."]

        case (.french, .reverseCharge):
            return ["Autoliquidation — TVA due par le preneur.",
                    "Article 283-2 du CGI ; article 196 de la directive 2006/112/CE."]
        case (.french, .intraCommunitySupply):
            return ["Livraison intracommunautaire exonérée.",
                    "Article 262 ter I du CGI ; article 138 de la directive 2006/112/CE."]
        case (.french, .export):
            return ["Exportation exonérée de TVA (article 262 I du CGI)."]
        case (.french, .smallBusiness):
            return ["TVA non applicable, article 293 B du CGI."]
        case (.french, .exempt):
            return ["Opération exonérée de TVA."]

        case (.italian, .reverseCharge):
            return ["Inversione contabile — IVA assolta dal committente.",
                    "Articolo 17 del DPR 633/72 ; articolo 196 della direttiva 2006/112/CE."]
        case (.italian, .intraCommunitySupply):
            return ["Cessione intracomunitaria non imponibile.",
                    "Articolo 41 del DL 331/93 ; articolo 138 della direttiva 2006/112/CE."]
        case (.italian, .export):
            return ["Operazione non imponibile (articolo 8 del DPR 633/72)."]
        case (.italian, .smallBusiness):
            return ["Operazione in regime forfettario, IVA non applicata."]
        case (.italian, .exempt):
            return ["Operazione esente IVA."]

        case (.spanish, .reverseCharge):
            return ["Inversión del sujeto pasivo — IVA a declarar por el destinatario.",
                    "Artículo 84 de la Ley 37/1992 ; artículo 196 de la Directiva 2006/112/CE."]
        case (.spanish, .intraCommunitySupply):
            return ["Entrega intracomunitaria exenta.",
                    "Artículo 25 de la Ley 37/1992 ; artículo 138 de la Directiva 2006/112/CE."]
        case (.spanish, .export):
            return ["Exportación exenta de IVA (artículo 21 de la Ley 37/1992)."]
        case (.spanish, .smallBusiness):
            return ["Operación sin IVA por régimen de franquicia."]
        case (.spanish, .exempt):
            return ["Operación exenta de IVA."]

        case (.dutch, .reverseCharge):
            return ["Btw verlegd — te voldoen door de afnemer.",
                    "Artikel 12 lid 3 Wet OB ; artikel 196 richtlijn 2006/112/EG."]
        case (.dutch, .intraCommunitySupply):
            return ["Intracommunautaire levering, 0% btw.",
                    "Tabel II post a6 Wet OB ; artikel 138 richtlijn 2006/112/EG."]
        case (.dutch, .export):
            return ["Uitvoer buiten de EU, 0% btw."]
        case (.dutch, .smallBusiness):
            return ["Geen btw in rekening gebracht — kleineondernemersregeling."]
        case (.dutch, .exempt):
            return ["Vrijgesteld van btw."]

        case (_, .standard):
            return []
        }
    }
}
