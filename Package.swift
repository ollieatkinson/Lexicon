// swift-tools-version: 6.3

import PackageDescription
import class Foundation.ProcessInfo
import struct Foundation.URL

let environment = ProcessInfo.processInfo.environment
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

func packagePath(_ path: String) -> String {
	path.hasPrefix("/") ? path : "\(packageRoot)/\(path)"
}

let onnxRuntimeRoot = packagePath(environment["LEXICON_ONNX_RUNTIME_ROOT"] ?? ".build/onnx-runtime/current")
let onnxRuntimePlatform = environment["LEXICON_ONNX_RUNTIME_PLATFORM"] ?? "linux-x64"
let onnxRuntimeLibrary = packagePath(environment["LEXICON_ONNX_RUNTIME_LIB"] ?? "\(onnxRuntimeRoot)/lib/\(onnxRuntimePlatform)")

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
		.library(name: "LexiconSearchONNX", targets: ["LexiconSearchONNX"]),
		.library(name: "SwiftLexicon", targets: ["SwiftLexicon"]),
		.library(name: "LexiconGenerators", targets: ["LexiconGenerators"]),
		.executable(name: "lexicon-generate", targets: ["lexicon-generate"]),
		.executable(name: "lexicon-lsp", targets: ["lexicon-lsp"]),
		.executable(name: "lexicon", targets: ["lexicon-cli"]),
		.plugin(name: "SwiftStandAloneGeneratorPlugin", targets: ["SwiftStandAloneGeneratorPlugin"]),
		.plugin(name: "SwiftLibraryGeneratorPlugin", targets: ["SwiftLibraryGeneratorPlugin"]),
		.plugin(name: "ONNXSearchArtifactsPlugin", targets: ["ONNXSearchArtifactsPlugin"]),
	],
	traits: [
		.trait(name: "Editor"),
		.trait(name: "MLXSearch"),
		.trait(name: "ONNXSearch"),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-collections", from: "1.5.1"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
		.package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.3"),
		.package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.3")),
		.package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
		.package(url: "https://github.com/DePasqualeOrg/swift-hf-api", exact: "0.3.2"),
		.package(url: "https://github.com/DePasqualeOrg/swift-hf-api-mlx", exact: "0.2.0"),
		.package(url: "https://github.com/DePasqualeOrg/swift-tokenizers", from: "0.6.3"),
		.package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
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
			swiftSettings: [.define("EDITOR", .when(traits: ["Editor"]))]
		),
		.testTarget(
			name: "LexiconTests",
			dependencies: [
				"Lexicon",
				"SwiftLexicon"
			],
			resources: [.copy("Resources")],
			swiftSettings: [.define("EDITOR", .when(traits: ["Editor"]))]
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
				.target(name: "LexiconSearchONNX", condition: .when(traits: ["ONNXSearch"])),
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
				.product(name: "HFAPI", package: "swift-hf-api", condition: .when(traits: ["MLXSearch"])),
				.product(name: "MLXEmbeddersHFAPI", package: "swift-hf-api-mlx", condition: .when(traits: ["MLXSearch"])),
				.product(name: "Tokenizers", package: "swift-tokenizers", condition: .when(traits: ["MLXSearch"])),
			]
		),
		.target(
			name: "LexiconSearchONNX",
			dependencies: [
				"Lexicon",
				.product(
					name: "onnxruntime",
					package: "onnxruntime-swift-package-manager",
					condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])
				),
				.target(
					name: "CLexiconONNXRuntime",
					condition: .when(platforms: [.linux, .android])
				),
			]
		),
		.target(
			name: "CLexiconONNXRuntime",
			publicHeadersPath: "include",
			cSettings: [
				.define("LEXICON_ONNX_RUNTIME_LIBRARY_PATH", to: "\"\(onnxRuntimeLibrary)/libonnxruntime.so\"")
			]
		),
		.testTarget(
			name: "LexiconSearchONNXTests",
			dependencies: [
				"Lexicon",
				"LexiconSearchONNX",
			]
		),
		.executableTarget(
			name: "onnx-search-artifacts",
			dependencies: ["LexiconSearchONNX"]
		),
		.plugin(
			name: "ONNXSearchArtifactsPlugin",
			capability: .command(
				intent: .custom(
					verb: "setup-onnx-search-artifacts",
					description: "Download ONNX search model and runtime artifacts."
				),
				permissions: [
					.writeToPackageDirectory(reason: "Stores ONNX search artifacts under .build/onnx-search and .build/onnx-runtime.")
				]
			),
			dependencies: ["onnx-search-artifacts"]
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
