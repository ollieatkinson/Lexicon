// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "LexiconMLXIntegration",
	platforms: [
		.macOS(.v15)
	],
	dependencies: [
		.package(
			name: "Lexicon",
			path: "../..",
			traits: [.defaults, "MLXSearch"]
		)
	],
	targets: [
		.testTarget(
			name: "LexiconMLXIntegrationTests",
			dependencies: [
				.product(name: "Lexicon", package: "Lexicon"),
				.product(name: "LexiconSearchMLX", package: "Lexicon")
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			]
		)
	],
	swiftLanguageModes: [.v6]
)
