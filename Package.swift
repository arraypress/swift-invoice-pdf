// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-invoice-pdf",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "InvoicePDF", targets: ["InvoicePDF"]),
    ],
    dependencies: [
        // The writer. This package is the paperwork; that one is the page.
        .package(url: "https://github.com/arraypress/swift-text-pdf.git", from: "2.3.0"),
        // Exact amounts, and the country facts an invoice turns on.
        .package(url: "https://github.com/arraypress/swift-money.git", from: "1.1.0"),
        .package(url: "https://github.com/arraypress/swift-countries.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "InvoicePDF",
            dependencies: [
                .product(name: "TextPDF", package: "swift-text-pdf"),
                .product(name: "Money", package: "swift-money"),
                .product(name: "Countries", package: "swift-countries"),
            ]
        ),
        .testTarget(
            name: "InvoicePDFTests",
            dependencies: [
                "InvoicePDF",
                .product(name: "TextPDF", package: "swift-text-pdf"),
                .product(name: "Money", package: "swift-money"),
                .product(name: "Countries", package: "swift-countries"),
            ]
        ),
    ]
)
