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
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.2")
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
				"SwiftLexicon",
				"SwiftStandAlone",
				"KotlinStandAlone",
        "TypeScriptStandAlone"
			]
		),
		.target(
			name: "SwiftLexicon",
			dependencies: [
				"Lexicon"
			]
		),
		.testTarget(
			name: "SwiftLexiconTests",
			dependencies: [
				"Hope",
				"SwiftLexicon"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "SwiftStandAlone",
			dependencies: [
				"Lexicon",
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
				"Lexicon",
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
				"Lexicon",
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
	// TODO: switch to Swift 6 language mode after porting SwiftLexicon events off Combine.
	swiftLanguageModes: [.v5]
)
