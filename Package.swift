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
		.library(name: "LexiconSearchMLX", targets: ["LexiconSearchMLX"]),
		.library(name: "SwiftLexicon", targets: ["SwiftLexicon"]),
		.library(name: "LexiconGenerators", targets: ["LexiconGenerators"]),
		.executable(name: "lexicon-generate", targets: ["lexicon-generate"]),
		.executable(name: "lexicon-lsp", targets: ["lexicon-lsp"]),
		.executable(name: "lexicon", targets: ["lexicon-cli"]),
		.plugin(name: "SwiftStandAloneGeneratorPlugin", targets: ["SwiftStandAloneGeneratorPlugin"]),
		.plugin(name: "SwiftLibraryGeneratorPlugin", targets: ["SwiftLibraryGeneratorPlugin"]),
	],
	traits: [
		.trait(name: "MLXSearch"),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-collections", from: "1.5.1"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
		.package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.3"),
		.package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.3")),
		.package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
		.package(url: "https://github.com/DePasqualeOrg/swift-hf-api-mlx", exact: "0.2.0"),
		.package(url: "https://github.com/DePasqualeOrg/swift-tokenizers", from: "0.6.3"),
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
				.product(name: "Algorithms", package: "swift-algorithms"),
				.product(name: "Collections", package: "swift-collections")
			],
			swiftSettings: [.define("EDITOR")] // TODO: make this opt in
		),
		.testTarget(
			name: "LexiconTests",
			dependencies: [
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
				"Lexicon"
			]
		),
		.target(
			name: "LexiconLSP",
			dependencies: [
				"Lexicon"
			]
		),
		.testTarget(
			name: "LexiconLSPTests",
			dependencies: [
				"LexiconLSP"
			]
		),
		.testTarget(
			name: "LexiconGeneratorsTests",
			dependencies: [
				"LexiconGenerators"
			],
			resources: [.copy("Resources")]
		),
		.target(
			name: "SwiftLexicon",
			dependencies: [
				"Lexicon",
				"_JSON",
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
			]
		),
		.testTarget(
			name: "SwiftLexiconTests",
			dependencies: [
				"SwiftLexicon",
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
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
		.executableTarget(
			name: "lexicon-lsp",
			dependencies: [
				"LexiconLSP",
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		),
		.executableTarget(
			name: "lexicon-cli",
			dependencies: [
				"Lexicon",
				.target(name: "LexiconSearchMLX", condition: .when(traits: ["MLXSearch"])),
				"LexiconGenerators",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
			]
		),
		.target(
			name: "LexiconSearchMLX",
			dependencies: [
				"Lexicon",
				.product(name: "MLX", package: "mlx-swift", condition: .when(traits: ["MLXSearch"])),
				.product(name: "MLXEmbedders", package: "mlx-swift-lm", condition: .when(traits: ["MLXSearch"])),
				.product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(traits: ["MLXSearch"])),
				.product(name: "MLXEmbeddersHFAPI", package: "swift-hf-api-mlx", condition: .when(traits: ["MLXSearch"])),
				.product(name: "Tokenizers", package: "swift-tokenizers", condition: .when(traits: ["MLXSearch"])),
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
