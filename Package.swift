// swift-tools-version: 5.6

import PackageDescription

let package = Package(
	name: "Lexicon",
	platforms: [
		.macOS(.v11),
		.iOS(.v14)
	],
	products: [
		.library(name: "Lexicon", targets: ["Lexicon"]),
		.library(name: "SwiftLexicon", targets: ["SwiftLexicon"]),
		.library(name: "LexiconGenerators", targets: ["LexiconGenerators"]),
		.executable(name: "lexicon-generate", targets: ["lexicon-generate"]),
		.plugin(name: "SwiftStandAloneGeneratorPlugin", targets: ["SwiftStandAloneGeneratorPlugin"]),
		.plugin(name: "SwiftLibraryGeneratorPlugin", targets: ["SwiftLibraryGeneratorPlugin"]),
	],
	dependencies: [
		.package(url: "https://github.com/screensailor/Hope", branch: "trunk"),
		.package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.2")
	],
	targets: [
		.target(
			name: "Lexicon",
			dependencies: [
				.product(name: "Collections", package: "swift-collections")
			],
			swiftSettings: [.define("EDITOR")] // TODO: make this opt in
		),
		.testTarget(
			name: "LexiconTests",
			dependencies: [
				"Hope",
				"Lexicon"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "LexiconGenerators",
			dependencies: [
				"Lexicon"
			]
		),
		.testTarget(
			name: "LexiconGeneratorsTests",
			dependencies: [
				"Hope",
				"LexiconGenerators"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "SwiftLexicon"
		),
		.testTarget(
			name: "SwiftLexiconTests",
			dependencies: [
				"Hope",
				"Lexicon",
				"SwiftLexicon"
			],
			resources: [.copy("Resources")]
		),
		.executableTarget(
			name: "lexicon-generate",
			dependencies: [
				.target(name: "LexiconGenerators"),
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "Collections", package: "swift-collections")
			]
		),
		.plugin(
			name: "SwiftStandAloneGeneratorPlugin",
			capability: .buildTool(),
			dependencies: ["lexicon-generate"]
		),
		.plugin(
			name: "SwiftLibraryGeneratorPlugin",
			capability: .buildTool(),
			dependencies: ["lexicon-generate"]
		)
	]
)
