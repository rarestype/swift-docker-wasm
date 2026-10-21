// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

// A library that uses a macro, built with `--product` like Y2K’s builds, to check
// that SwiftPM uses prebuilt swift-syntax instead of compiling it.
let package: Package = .init(
    name: "swift-macros-test",
    products: [
        .library(name: "Probe", targets: ["Probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "603.0.2"),
    ],
    targets: [
        .macro(
            name: "ProbeMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(name: "Probe", dependencies: ["ProbeMacros"]),
    ]
)
