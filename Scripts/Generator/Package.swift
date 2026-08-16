// swift-tools-version: 5.9
//
//  The documents the validator marks.
//
//  Its own package rather than a target of the library's: it exists to be
//  run by hand against a validator that is not a dependency, and nothing
//  that builds the library should have to build it.
//
import PackageDescription

let package = Package(
    name: "generator",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "generator",
            dependencies: [.product(name: "InvoicePDF", package: "swift-invoice-pdf")]
        ),
    ]
)
