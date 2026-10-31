// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "LexiconPluginIntegration",
	platforms: [.macOS(.v15)],
	dependencies: [.package(name: "Lexicon", path: "../..")],
	targets: [
		.target(
			name: "LibraryPluginFixture",
			dependencies: [
				.product(name: "SwiftLexicon", package: "Lexicon")
			],
			exclude: [
				"North/catalog.notlexicon",
				"North/Parts"
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
			exclude: ["Nested/Parts"],
			swiftSettings: [
				.treatAllWarnings(as: .error)
			],
			plugins: [
				.plugin(name: "SwiftStandAloneGeneratorPlugin", package: "Lexicon")
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
