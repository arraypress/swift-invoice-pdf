//
//  main.swift
//  generator
//
//  Created by David Sherlock on 2026.
//
//  One document for every shape the library can produce.
//
//  The matrix rather than an example, because an element in the wrong place
//  only fails in the document that carries it: the sequence error in the tax
//  block was invisible until an exempt invoice was rendered, since only an
//  exempt one writes an exemption reason.
//

import Countries
import Foundation
import InvoicePDF
import Money

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let issued = Date(timeIntervalSince1970: 1_785_000_000)

let seller = Party(
    name: "SwiftInvoices Ltd",
    address: ["71–75 Shelton Street", "London WC2H 9JQ"],
    email: "billing@swiftinvoices.example", taxID: "GB123456789",
    country: Country("GB")
)
let buyer = Party(
    name: "Klangwerk GmbH",
    address: ["Oranienburger Strasse 87", "10178 Berlin"],
    taxID: "DE811567890", country: Country("DE")
)

var written = 0, refused: [String] = []

for treatment in VatTreatment.allCases {
    for profile in FacturX.Profile.allCases {
        for (label, currency) in [("gbp", Currency.gbp), ("jpy", Currency.jpy),
                                  ("kwd", Currency("KWD"))] {
            let sums = Totals(
                lines: [
                    .init("Licence", unitPrice: Money(units: 149 * currency.unitsPerMajor,
                                                      in: currency)),
                    .init("Support", quantity: 3,
                          unitPrice: Money(units: 70 * currency.unitsPerMajor, in: currency)),
                ],
                rate: treatment == .standard ? 20 : 0,
                currency: currency
            )

            // With every optional piece and then with none, since an element
            // out of place only fails where it is present.
            for (suffix, reference, due) in [
                ("full", "PO-4471", Optional(issued.addingTimeInterval(30 * 86_400))),
                ("bare", "", nil),
            ] {
                let invoice = Invoice(
                    branding: Branding(name: "SwiftInvoices Ltd"),
                    number: "INV-2026-0042", from: seller, to: buyer,
                    items: sums.items(), totals: sums.rows(),
                    total: [("Total due", sums.gross.formatted())],
                    vat: treatment, vatLines: sums.vatLines(), reference: reference
                )

                var details = sums.facturX(profile: profile, issued: issued, due: due,
                                           buyerReference: reference)
                if treatment == .intraCommunitySupply {
                    details.delivered = issued
                    details.deliveredTo = buyer.country
                }

                let name = "\(treatment)-\(profile == .minimum ? "min" : "bwl")-\(label)-\(suffix)"
                do {
                    try invoice.facturX(details)
                        .write(to: out.appendingPathComponent("\(name).xml"))
                    written += 1
                } catch {
                    refused.append(name)
                }
            }
        }
    }
}

print("\(written) documents written, \(refused.count) refused")
if !refused.isEmpty {
    // Named rather than counted: a refusal the library means (the dinar, which
    // EN 16931 cannot express) looks exactly like one it does not.
    print("refused: \(refused.map { $0.components(separatedBy: "-").suffix(2).joined(separator: "-") }.sorted().first ?? "") …")
}
