# Swift Invoice PDF

Business documents as PDFs: invoices, statements, timesheets, royalty statements, aged analyses and customs paperwork — with the VAT wording and the compliance checks that decide whether the recipient can rely on them.

```swift
let invoice = Invoice(
    branding: branding,
    number: "INV-2026-0042",
    from: seller,
    to: buyer,
    items: items,
    totals: [("Subtotal", "£856.00"), ("VAT at 20%", "£154.08")],
    total: [("Total due", "£924.48")]
)
try invoice.save(to: url)     // 7 KB
```

## Why

The part worth having is not the PDF writing — that is [swift-text-pdf](https://github.com/arraypress/swift-text-pdf), underneath. It is knowing what has to be on the page.

A credit note that does not reference the invoice it reverses, or a self-billed invoice missing the words "self-billing", can be refused as evidence for the recipient's input-tax deduction. That becomes their problem and your support ticket. `complianceWarnings(verifying:)` reads the finished page and tells you before you send.

## Features

- 🧾 **Twelve invoice kinds** — invoice, credit note, debit note, quote, proforma, receipt, reminder, remittance advice, self-billed invoice, delivery note, purchase order, order confirmation
- 📚 **Six document types** — invoice, statement of account, timesheet, royalty statement, aged debtors or creditors, and the pair that cross a border
- 🇪🇺 **VAT-aware** — reverse charge, intra-community supply, export and small-business wording, in English plus German, French, Italian, Spanish or Dutch — each citing its own statute
- ✅ **Compliance checks** — the §14 UStG / Article 226 particulars, verified against the drawn page rather than the model
- ✒️ **Your own typeface** — set the documents in a brand family, with a reported fallback for anything it cannot draw
- 🖼️ **Vector logos** — an SVG `path`, sharp at any zoom
- 📄 **Multi-page** — headings repeat, footers know the total
- ▦ **Payment codes** — an EPC code for a SEPA transfer, or any payload; drawn as vector, so it scans off a photocopy
- 🇪🇺 **Factur-X / ZUGFeRD** — the invoice as XML inside a PDF/A-3, which is what an e-invoice is
- 🪶 **Three small dependencies** — the writer, the money and the country table; the writer itself has none

## Scan to pay

A transposed IBAN digit is a payment that bounces a week later; a missing reference is one nobody can match to an invoice. A code removes both.

```swift
let code = PaymentCode.epc(
    beneficiary: "SwiftInvoices Ltd",
    iban: "DE89 3704 0044 0532 0130 00",
    amount: 677.11,
    reference: "INV-2026-0044"
)
Invoice(…, paymentCode: code)
```

`epc` builds what a European banking app expects and enforces the rules that bite — euro only, the name capped at 70 characters, the reference at 140 — returning `nil` rather than a code that shows an error instead of a payment. Anything else is a payload you supply: a payment page, a card processor's URL, a Swiss QR-bill string.

The code is drawn beside the payment wording, and the wording is set to a narrower measure so the two never collide. [Examples](Examples/invoices/qr-sepa.pdf).

## The wording, in the language that reads it

```swift
Invoice(…, vat: .reverseCharge, wording: .french)
```

```
Reverse charge: VAT to be accounted for by the recipient.
Article 196, Council Directive 2006/112/EC.
Autoliquidation — TVA due par le preneur.
Article 283-2 du CGI ; article 196 de la directive 2006/112/CE.
```

English always, and a second language beside it — the person reading the invoice and the authority checking it are often not the same person. Each language cites its own statute rather than only the directive: an inspector expects the article of their own code, and `§ 13b UStG`, `article 283-2 du CGI` and `articolo 17 del DPR 633/72` are what the phrase means locally.

**Not legal advice, and worth a professional's eye before you rely on it.** These are the standard formulations, which are published and formulaic — but a wrong phrase in a language you do not read is worse than an English one you do. [One example per language](Examples/wording).

## Working the figures out

Give the lines as money and everything follows from them — the page and the XML from the same integers, so they cannot disagree:

```swift
let sums = Totals(
    lines: [
        .init("Document generation licence", unitPrice: Money("149.00", in: .gbp)!),
        .init("Template design and setup", quantity: 6, unitPrice: Money("70.00", in: .gbp)!),
    ],
    rate: 20,
    currency: .gbp
)

sums.net      // £749.00
sums.tax      // £149.80
sums.gross    // £898.80

Invoice(…, items: sums.items(), totals: sums.rows(), vatLines: sums.vatLines())
try invoice.facturX(sums.facturX(issued: issuedDate))
```

Before this, an e-invoice made you write every figure twice — once as a string for the page and once as a number for the XML — with nothing checking that the two agreed. Now nobody writes them twice, so nothing can be written twice differently.

Built on [swift-money](https://github.com/arraypress/swift-money), which counts in the currency's smallest unit and knows how many that is.

## Checked against a real validator

The XML goes through the published conformance tools, not just our own tests:

```sh
Scripts/validate-facturx.sh
```

It fetches the UN/CEFACT **CII D16B schema** and the **Factur-X profile rules** as Schematron, generates a document for every VAT treatment, profile and currency, and marks each one. Nothing is uploaded — the artefacts are public, the invoices stay on your machine. Needs `python3` and `xmllint`, both of which ship with macOS; Saxon arrives through pip, so there is no JDK.

The first run of it found five things this library got wrong, all of which looked right and passed every test:

| Finding | What it was |
|---|---|
| **BR-09** | Every document was missing the seller's country, and would have been rejected outright. It was read off the last address line where that line was two capitals — which finds nothing in "London WC2H 9JQ" and finds Canada in "Sacramento, CA". `Party(country:)` now states it. |
| **Sequence** | `ExemptionReason` was written after `CategoryCode` — the reason beside the code it explains, which reads well and is invalid. CII declares a sequence; a reader stops at the first element out of place. |
| **Minimum** | Carried the buyer's address and tax registration, neither of which that profile permits. |
| **BR-IC-11/12** | An intra-community supply claimed a zero rate without saying which border the goods crossed or when. `FacturX(delivered:deliveredTo:)` now carries both, and the document is refused without them. |
| **BR-DEC-09…20** | EN 16931 caps every document amount at **two** decimals whatever the currency's minor unit is — so an e-invoice in Kuwaiti dinars is impossible, and is now refused rather than quietly rounded. |

## Money, and how many decimals it has

Every amount printed on the page is a string, so `¥1,234` and `€1.234,56` pass through exactly as written — formatting money means knowing a currency's separators and symbol placement, and that belongs where the money lives.

The figures given for an e-invoice are `Decimal`, not cents, and they are written to **the number of places their currency actually has**:

| Currency | Places it is written to |
|---|---|
| `JPY`, `KRW`, `ISK`, `CLP`, `VND`, `XOF`… | none — `1000`, not `1000.00` |
| most | two — `898.80` |
| `KWD`, `BHD`, `OMR`, `TND`, `JOD`, `IQD`, `LYD` | three — `1.234` |
| `CLF`, `UYW` | four |

Two places was hard-coded before, which wrote the yen with decimals it does not have and **silently dropped a fils** off a Kuwaiti dinar — money going missing from a tax document rather than a formatting quibble.

> On the **page**, all of the above holds. In **Factur-X**, it does not: EN 16931 caps document-level amounts at two decimals (BR-DEC-09 to BR-DEC-20) regardless of currency, so the three- and four-place currencies cannot be e-invoiced at all. `facturX()` refuses them by name rather than rounding a fils away where nobody would see it.

Amounts finer than their currency are **rounded, not refused**: 20% of 1234.56 is 246.912, and every accounting system writes 246.91. The totals are then checked as the document prints them, because that is what a customer adds up.

> `Decimal` from a float literal goes through `Double`, so `1234.56` arrives as `1234.5599999999997952`. It rounds and prints correctly, and the checks allow for it — but `Decimal(string: "1234.56")` is exact, and exact is what money deserves in code that adds it up.

## Totals that add up

The figures given for an e-invoice are checked against each other before anything is written:

```
This cannot be sent as an e-invoice: The total does not add up:
GBP 749.00 plus GBP 149.80 is GBP 898.80, and the gross says GBP 890.00.
```

It is the only arithmetic that can be checked here — every amount printed on the page is a string, deliberately — but those four numbers arrived as numbers, and net plus tax is gross wherever you are. A penny either way is rounding; more is a mistake, and a total that does not add up is the first thing a customer notices.

## E-invoicing

Germany's mandate is phasing in, France's follows, Italy's has been running for years. All of them want the *structured* invoice, and Factur-X — ZUGFeRD in Germany, the same specification — says how: one PDF/A-3 carrying the invoice as XML. The page is what a person reads; the attachment is what the buyer's ledger reads.

```swift
let data = try invoice.facturXDocument(
    FacturX(
        currency: "GBP",
        issued: issuedDate,
        due: dueDate,
        totals: .init(net: 749, tax: 149.80, gross: 898.80),
        taxRate: 20,
        buyerReference: "PO-4471"
    ),
    in: family
)
```

One file, both halves, claiming PDF/A-3 and meeting it. There is [an example](Examples/e-invoice) with the XML beside it.

**The figures are given rather than taken.** Every amount on an `Invoice` is a string, deliberately — formatting money means knowing a currency's separators, and that belongs where the money lives. The XML wants the opposite: a decimal a machine adds up. Reading `"£1.234,56"` back into a number means guessing whether that comma is a decimal point, and a guess wrong by a factor of a thousand on a tax return is not one worth making. So you pass the numbers you already had before formatting them.

**It refuses rather than producing something a buyer's system will reject** — a delivery note has no invoice form, a missing supplier VAT number is fatal, reverse charge needs the customer's. The rejection would otherwise arrive days later, against your name.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-invoice-pdf.git", from: "0.1.0")
```

## Examples

Every kind and every document type, [as PDFs you can open](Examples) before installing anything.

## Documents

Six types, because these are genuinely different documents rather than one document with the words changed.

| Type | For |
|---|---|
| `Invoice` | billing, in twelve kinds — see below |
| `Statement` | an account over a period: charges, payments, running balance, aged analysis |
| `Timesheet` | time worked, by day and project — the evidence behind an invoice, and signed by someone else |
| `RoyaltyStatement` | what a contributor earned, and what is actually payable after recoupment |
| `AgedAnalysis` | who owes what, or who you owe — internal, not sent |
| `Consignment` | a commercial invoice or a packing list, for goods crossing a border |

### Invoice kinds

| Kind | For |
|---|---|
| `invoice` | the tax invoice |
| `creditNote` | reversing one — you cannot amend an invoice, so a refund cites it |
| `debitNote` | charging more against an earlier invoice |
| `quote` | pre-sale, no VAT due |
| `proforma` | advance payment; not a tax invoice, and says so |
| `receipt` | proof of payment |
| `reminder` | chasing an overdue invoice |
| `remittance` | telling a supplier what you have just paid, and against what |
| `selfBilling` | the buyer raising the invoice, by prior agreement |
| `deliveryNote` | what was sent, with no prices |
| `purchaseOrder` | ordering |
| `orderConfirmation` | acknowledging an order |

### Royalty statements

Earnings and payment are not the same number, and a statement showing only one of them is why royalty statements have the reputation they do. The template lays out the whole chain — what the distributor sold, what it kept, what reached you, the contributor's split — and then the reconciliation from opening unrecouped balance to what is payable now.

Where nothing is payable, `carriedForwardNote` prints the reason on the document. A statement with earnings and no payment reads as a withholding unless it says otherwise, and that explanation should not live in a covering email.

### Crossing a border

`Consignment` produces a commercial invoice or a packing list. These carry fields a sales invoice has no notion of — a tariff heading and country of origin per line, the delivery term with its named place, net and gross weights — because a customs officer values the consignment from them.

A packing list carries no prices at all. That is the difference between the two documents, not a formatting option: the list is read by people handling the boxes, and in some trades it reaches the buyer's customer.

`complianceWarnings(verifying:)` checks the finished document rather than the data. That distinction matters on an invoice: a recipient's input-tax deduction turns on wording being *printed*, and a template that stopped drawing it would pass every check that only reads the invoice's fields.

`complianceWarnings()` checks what the template can see: supplier tax number, both addresses, a sequential number, the date of supply, the customer VAT number where the treatment requires it, and — for a credit note — the invoice it reverses.

`Consignment` has its own, covering the commodity code, origin and weight on every line, the delivery term and the reason for export.

Not tax advice, and not exhaustive. Both verify that the particulars are present, not that they are right — no template can tell whether a commodity code is the correct heading for what is in the box.

## Money is a string, deliberately

Every amount is pre-formatted. Rendering money correctly means knowing the currency's decimal exponent, its thousands convention and its symbol placement, and a layout type has no business guessing at any of that. Format it where the money lives and pass the result.


## A typeface of your own

Business documents default to Helvetica because paperwork is better for being unremarkable — it prints on anything, photocopies, and is hard to date. Where a business has a face of its own, name it on the branding:

```swift
let branding = Branding(
    name: "SwiftInvoices Ltd",
    typeface: TypefaceFiles(name: "Söhne", regular: regularPath, bold: boldPath)
)
try Invoice(branding: branding, …).save(to: url)
```

Only the weights named exist; a template asking for bold in a profile with one file gets that file, so a business with a single face still gets its documents set in it.

A brand face drawn for a logo commonly has no `£` or `€`. Those runs fall back to Helvetica and appear correctly — but in a different face, and on a total that is the one figure nobody should have to look at twice. Anything the family could not draw is listed in `document.fallbacks` after rendering, so it can be reported rather than found.


## Requirements

- macOS 14+ / iOS 17+
- Swift 6

## Built on

- [swift-text-pdf](https://github.com/arraypress/swift-text-pdf) — the writer: text flow, tables, curves, typefaces, images
- [swift-money](https://github.com/arraypress/swift-money) — exact amounts, in the currency's smallest unit
- [swift-countries](https://github.com/arraypress/swift-countries) — the country field an e-invoice cannot do without

## License

MIT — see [LICENSE](LICENSE).
