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
        .package(url: "https://github.com/arraypress/swift-text-pdf.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "InvoicePDF",
            dependencies: [.product(name: "TextPDF", package: "swift-text-pdf")]
        ),
        .testTarget(
            name: "InvoicePDFTests",
            dependencies: ["InvoicePDF", .product(name: "TextPDF", package: "swift-text-pdf")]
        ),
    ]
)
