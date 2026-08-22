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
		.target(
			name: "LibraryPluginFixture",
			dependencies: [
				.product(name: "SwiftLexicon", package: "Lexicon")
			],
			exclude: [
				"North/catalog.notlexicon"
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			],
			plugins: [
				.plugin(name: "SwiftLibraryGeneratorPlugin", package: "Lexicon")
			]
		),
		.target(
			name: "StandalonePluginFixture",
			swiftSettings: [
				.treatAllWarnings(as: .error)
			],
			plugins: [
				.plugin(name: "SwiftStandAloneGeneratorPlugin", package: "Lexicon")
			]
		),
		.testTarget(
			name: "LexiconMLXIntegrationTests",
			dependencies: [
				.product(name: "Lexicon", package: "Lexicon"),
				.product(name: "LexiconSearchMLX", package: "Lexicon")
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			]
		),
		.testTarget(
			name: "LibraryPluginIntegrationTests",
			dependencies: [
				"LibraryPluginFixture"
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			]
		),
		.testTarget(
			name: "StandalonePluginIntegrationTests",
			dependencies: [
				"StandalonePluginFixture"
			],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			]
		)
	],
	swiftLanguageModes: [.v6]
)
