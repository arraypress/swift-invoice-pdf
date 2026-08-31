//
//  SupportRuleTests.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  The extracted rules, pinned directly — no Totals, no Party, no
//  VatTreatment value is constructed where the rule alone will do.
//

import Countries
import Foundation
import Money
import XCTest
@testable import InvoicePDF

final class SupportRuleTests: XCTestCase {

    func testPercentageWritesRatesAsWritten() {
        XCTAssertEqual(TotalsFigures.percentage(20), "20")
        XCTAssertEqual(TotalsFigures.percentage(Decimal(string: "19.5")!), "19.5")
        XCTAssertEqual(TotalsFigures.percentage(Decimal(string: "20.00")!), "20")
    }

    func testTaxIsTakenOnTheTotal() {
        let net = Money("749.00", in: .gbp)!
        XCTAssertEqual(TotalsFigures.tax(on: net, rate: 20, rounding: .half).decimalString, "149.80")
        // The penny case the rule exists for: 0.99 at 20% is 0.198, which
        // rounds half-away to 0.20 on the total.
        let small = Money("0.99", in: .gbp)!
        XCTAssertEqual(TotalsFigures.tax(on: small, rate: 20, rounding: .half).decimalString, "0.20")
    }

    func testStatutoryWordingsAreExact() {
        XCTAssertEqual(
            VatWording.notes(for: .reverseCharge, in: .german),
            ["Steuerschuldnerschaft des Leistungsempf\u{00E4}ngers (\u{00A7} 13b UStG)."]
        )
        XCTAssertEqual(VatWording.english(.export), ["Zero-rated export outside the European Union."])
        for language in VatTreatment.Wording.allCases {
            XCTAssertTrue(VatWording.notes(for: .standard, in: language).isEmpty)
        }
    }

    func testPartyLinesSkipBlanksAndTrimTheMailto() {
        let linked = PartyLines.linked(address: ["  "], email: " a@b.c ", taxID: "", vatLabel: "VAT")
        XCTAssertEqual(linked.count, 1, "a blank address line is not a row")
        XCTAssertEqual(linked[0].url, "mailto:a@b.c", "the link is trimmed even where the text is not")
        XCTAssertEqual(PartyLines.plain(address: ["1 Road"], email: "", taxID: "GB1", vatLabel: "VAT"),
                       ["1 Road", "VAT GB1"])
    }
}
