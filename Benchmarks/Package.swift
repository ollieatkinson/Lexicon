// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "LexiconBenchmarks",
	platforms: [
		.macOS(.v15)
	],
	products: [
		.executable(name: "LexiconBenchmarks", targets: ["LexiconBenchmarks"]),
	],
	dependencies: [
		.package(path: ".."),
		.package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMinor(from: "1.29.11")),
	],
	targets: [
		.executableTarget(
			name: "LexiconBenchmarks",
			dependencies: [
				.product(name: "Benchmark", package: "package-benchmark"),
				.product(name: "Lexicon", package: "Lexicon"),
				.product(name: "_Collections", package: "Lexicon"),
			],
			path: "LexiconBenchmarks",
			plugins: [
				.plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
			]
		),
	],
	swiftLanguageModes: [.v6]
)
