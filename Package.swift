// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "Lexicon",
	platforms: [
		.macOS(.v15),
		.iOS(.v18)
	],
	products: [
		.library(name: "_Collections", targets: ["_Collections"]),
		.library(name: "_JSON", targets: ["_JSON"]),
		.library(name: "Lexicon", targets: ["Lexicon"]),
		.library(name: "SwiftLexicon", targets: ["SwiftLexicon"]),
		.library(name: "SwiftStandAlone", targets: ["SwiftStandAlone"]),
		.library(name: "KotlinStandAlone", targets: ["KotlinStandAlone"]),
		.library(name: "TypeScriptStandAlone", targets: ["TypeScriptStandAlone"]),
		.library(name: "LexiconGenerators", targets: ["LexiconGenerators"]),
		.executable(name: "lexicon-generate", targets: ["lexicon-generate"]),
		.plugin(name: "SwiftStandAloneGeneratorPlugin", targets: ["SwiftStandAloneGeneratorPlugin"]),
		.plugin(name: "SwiftLibraryGeneratorPlugin", targets: ["SwiftLibraryGeneratorPlugin"]),
	],
	dependencies: [
		.package(url: "https://github.com/screensailor/Hope", branch: "trunk"),
		.package(url: "https://github.com/apple/swift-collections", from: "1.5.1"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
		.package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.3")
	],
	targets: [
		.target(
			name: "_Collections",
			dependencies: [
				.product(name: "Collections", package: "swift-collections")
			]
		),
		.target(
			name: "_JSON"
		),
		.target(
			name: "Lexicon",
			dependencies: [
				"_Collections",
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
		.testTarget(
			name: "_CollectionsTests",
			dependencies: ["_Collections"]
		),
		.testTarget(
			name: "_JSONTests",
			dependencies: ["_JSON"]
		),
		.target(
			name: "LexiconGenerators",
			dependencies: [
				"Lexicon",
				"SwiftLexicon"
			]
		),
		.testTarget(
			name: "LexiconGeneratorsTests",
			dependencies: [
				"Hope",
				"LexiconGenerators"
			]
		),
		.target(
			name: "SwiftLexicon",
			dependencies: [
				"Lexicon",
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
			]
		),
		.testTarget(
			name: "SwiftLexiconTests",
			dependencies: [
				"Hope",
				"SwiftLexicon",
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "SwiftStandAlone",
			dependencies: [
				"LexiconGenerators",
			]
		),
		.testTarget(
			name: "SwiftStandAloneTests",
			dependencies: [
				"Hope",
				"SwiftStandAlone"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "KotlinStandAlone",
			dependencies: [
				"LexiconGenerators",
			]
		),
		.testTarget(
			name: "KotlinStandAloneTests",
			dependencies: [
				"Hope",
				"KotlinStandAlone"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "TypeScriptStandAlone",
			dependencies: [
				"LexiconGenerators",
			]
		),
		.testTarget(
			name: "TypeScriptStandAloneTests",
			dependencies: [
				"Hope",
				"TypeScriptStandAlone"
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
	],
	swiftLanguageModes: [.v6]
)
