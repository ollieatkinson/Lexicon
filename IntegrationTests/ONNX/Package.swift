// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "LexiconONNXIntegration",
	platforms: [
		.macOS(.v15),
		.iOS(.v18)
	],
	dependencies: [
		.package(
			name: "Lexicon",
			path: "../..",
			traits: [.defaults, "ONNXSearch"]
		)
	],
	targets: [
		.testTarget(
			name: "LexiconONNXIntegrationTests",
			dependencies: [
				.product(name: "Lexicon", package: "Lexicon"),
				.product(name: "LexiconSearchONNX", package: "Lexicon")
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			]
		)
	],
	swiftLanguageModes: [.v6]
)
