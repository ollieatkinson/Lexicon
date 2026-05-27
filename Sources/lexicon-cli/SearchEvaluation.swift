import ArgumentParser
import Foundation
import Lexicon

struct SearchEvaluate: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "search-evaluate",
		abstract: "Evaluate search quality against query judgments."
	)

	@Argument(help: "JSON file containing search quality suites.")
	var judgments: URL

	@Option(help: "Search mode: hybrid, token, lexical, semantic, or a comma-separated combination.")
	var mode = "hybrid"

	@Option(help: "Search scope: own, live, or full.")
	var scope = Lexicon.Search.Scope.own.rawValue

	@Option(help: "Maximum result rank used for metrics.")
	var limit = 10

	@Option(help: "Semantic embedding provider: auto, system, mlx, onnx, or none.")
	var embeddingProvider = "none"

	@Option(help: "Embedding model ID for MLX, or model path for ONNX semantic search.")
	var embeddingModel: String?

	@Option(help: "ONNX embedding model preset. Defaults to all-MiniLM-L6-v2.")
	var embeddingModelPreset: String?

	@Option(help: "ONNX embedding model manifest JSON path.")
	var embeddingModelManifest: URL?

	@Option(help: "Vocabulary path for ONNX semantic search.")
	var embeddingVocabulary: URL?

	@Option(help: "Model revision used in embedding cache identity.")
	var embeddingModelRevision: String?

	@Option(help: "Embedding cache path. Defaults to the user cache directory.")
	var embeddingCache: URL?

	@Flag(help: "Regenerate cached document embeddings before evaluating.")
	var rebuildEmbeddings = false

	@Flag(help: "Search source documents without composing imports.")
	var sourceOnly = false

	mutating func run() async throws {
		let file = try SearchJudgmentFile.load(from: judgments)
		let output = try await SearchQualityRun(
			judgments: file,
			baseURL: judgments.deletingLastPathComponent(),
			options: .init(
				mode: try Lexicon.Search.Mode(agentArgument: mode),
				scope: try Lexicon.Search.Scope(agentArgument: scope),
				limit: limit,
				embeddingProvider: try SearchEmbeddingProviderSelection(agentArgument: embeddingProvider),
				embeddingModel: embeddingModel,
				embeddingModelPreset: embeddingModelPreset,
				embeddingModelManifest: embeddingModelManifest,
				embeddingVocabulary: embeddingVocabulary,
				embeddingModelRevision: embeddingModelRevision,
				embeddingCache: embeddingCache,
				rebuildEmbeddings: rebuildEmbeddings,
				sourceOnly: sourceOnly
			)
		).evaluate()
		try AgentJSON.print(output)
	}
}

private struct SearchQualityRun {
	var judgments: SearchJudgmentFile
	var baseURL: URL
	var options: Options

	struct Options {
		var mode: Lexicon.Search.Mode
		var scope: Lexicon.Search.Scope
		var limit: Int
		var embeddingProvider: SearchEmbeddingProviderSelection
		var embeddingModel: String?
		var embeddingModelPreset: String?
		var embeddingModelManifest: URL?
		var embeddingVocabulary: URL?
		var embeddingModelRevision: String?
		var embeddingCache: URL?
		var rebuildEmbeddings: Bool
		var sourceOnly: Bool
	}

	func evaluate() async throws -> SearchQualityOutput {
		var suiteOutputs: [SearchQualitySuiteOutput] = []
		for suite in judgments.suites {
			suiteOutputs.append(try await evaluate(suite))
		}
		return .init(
			mode: options.mode.agentArgument,
			scope: options.scope.rawValue,
			limit: options.limit,
			embeddingProvider: options.embeddingProvider.rawValue,
			suites: suiteOutputs
		)
	}

	private func evaluate(_ suite: SearchJudgmentSuite) async throws -> SearchQualitySuiteOutput {
		let input = suite.inputURL(relativeTo: baseURL)
		let documentStart = Date()
		let document = try options.sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		let searchOptions = Lexicon.Search.Options(
			limit: options.limit,
			mode: options.mode,
			scope: options.scope
		)
		let indexStart = Date()
		let index = Lexicon.Search.Index(document: document, options: searchOptions)
		let indexSeconds = Date().timeIntervalSince(indexStart)
		var queryOutputs: [SearchQualityQueryOutput] = []
		for query in suite.queries {
			queryOutputs.append(try await evaluate(query, input: input, document: document, index: index))
		}
		return .init(
			name: suite.name,
			input: suite.input,
			documentSeconds: Date().timeIntervalSince(documentStart),
			indexSeconds: indexSeconds,
			cacheBytes: options.embeddingCache.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int },
			queries: queryOutputs
		)
	}

	private func evaluate(
		_ query: SearchJudgmentQuery,
		input: URL,
		document: Lexicon.Document,
		index: Lexicon.Search.Index
	) async throws -> SearchQualityQueryOutput {
		let started = Date()
		let results = try await index.search(
			query.query,
			in: document,
			input: input,
			embeddingProvider: options.embeddingProvider,
			embeddingModel: options.embeddingModel,
			embeddingModelPreset: options.embeddingModelPreset,
			embeddingModelManifest: options.embeddingModelManifest,
			embeddingVocabulary: options.embeddingVocabulary,
			embeddingModelRevision: options.embeddingModelRevision,
			embeddingCache: options.embeddingCache,
			rebuildEmbeddings: options.rebuildEmbeddings
		)
		let ids = results.map(\.id)
		let metrics = SearchQualityMetrics(results: ids, relevance: query.relevant, limit: options.limit)
		return .init(
			query: query.query,
			relevant: query.relevant,
			results: Array(ids.prefix(options.limit)),
			seconds: Date().timeIntervalSince(started),
			metrics: metrics
		)
	}
}

private struct SearchJudgmentFile: Codable {
	var suites: [SearchJudgmentSuite]

	static func load(from url: URL) throws -> Self {
		try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
	}
}

private struct SearchJudgmentSuite: Codable {
	var name: String
	var input: String
	var queries: [SearchJudgmentQuery]

	func inputURL(relativeTo baseURL: URL) -> URL {
		if input == "~" || input.hasPrefix("~/") {
			let suffix = input == "~" ? "" : String(input.dropFirst(2))
			return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(suffix)
		}
		if input.hasPrefix("/") {
			return URL(fileURLWithPath: input)
		}
		return baseURL.appendingPathComponent(input)
	}
}

private struct SearchJudgmentQuery: Codable {
	var query: String
	var relevant: [String: Double]
}

private struct SearchQualityOutput: Codable {
	var mode: String
	var scope: String
	var limit: Int
	var embeddingProvider: String
	var suites: [SearchQualitySuiteOutput]
	var metrics: SearchQualityMetrics

	init(
		mode: String,
		scope: String,
		limit: Int,
		embeddingProvider: String,
		suites: [SearchQualitySuiteOutput]
	) {
		self.mode = mode
		self.scope = scope
		self.limit = limit
		self.embeddingProvider = embeddingProvider
		self.suites = suites
		self.metrics = SearchQualityMetrics.average(suites.flatMap(\.queries).map(\.metrics))
	}
}

private struct SearchQualitySuiteOutput: Codable {
	var name: String
	var input: String
	var documentSeconds: Double
	var indexSeconds: Double
	var cacheBytes: Int?
	var queries: [SearchQualityQueryOutput]
	var metrics: SearchQualityMetrics

	init(
		name: String,
		input: String,
		documentSeconds: Double,
		indexSeconds: Double,
		cacheBytes: Int?,
		queries: [SearchQualityQueryOutput]
	) {
		self.name = name
		self.input = input
		self.documentSeconds = documentSeconds
		self.indexSeconds = indexSeconds
		self.cacheBytes = cacheBytes
		self.queries = queries
		self.metrics = SearchQualityMetrics.average(queries.map(\.metrics))
	}
}

private struct SearchQualityQueryOutput: Codable {
	var query: String
	var relevant: [String: Double]
	var results: [String]
	var seconds: Double
	var metrics: SearchQualityMetrics
}

private struct SearchQualityMetrics: Codable {
	var mrrAt10: Double
	var ndcgAt10: Double
	var recallAt10: Double

	init(results: [String], relevance: [String: Double], limit: Int) {
		let limited = Array(results.prefix(min(limit, 10)))
		mrrAt10 = Self.mrr(results: limited, relevance: relevance)
		ndcgAt10 = Self.ndcg(results: limited, relevance: relevance)
		recallAt10 = Self.recall(results: limited, relevance: relevance)
	}

	init(mrrAt10: Double, ndcgAt10: Double, recallAt10: Double) {
		self.mrrAt10 = mrrAt10
		self.ndcgAt10 = ndcgAt10
		self.recallAt10 = recallAt10
	}

	static func average(_ metrics: [Self]) -> Self {
		guard metrics.isEmpty == false else {
			return .init(mrrAt10: 0, ndcgAt10: 0, recallAt10: 0)
		}
		let count = Double(metrics.count)
		return .init(
			mrrAt10: metrics.reduce(0) { $0 + $1.mrrAt10 } / count,
			ndcgAt10: metrics.reduce(0) { $0 + $1.ndcgAt10 } / count,
			recallAt10: metrics.reduce(0) { $0 + $1.recallAt10 } / count
		)
	}

	private static func mrr(results: [String], relevance: [String: Double]) -> Double {
		for (index, id) in results.enumerated() where (relevance[id] ?? 0) > 0 {
			return 1.0 / Double(index + 1)
		}
		return 0
	}

	private static func recall(results: [String], relevance: [String: Double]) -> Double {
		let relevant = Set(relevance.filter { $0.value > 0 }.keys)
		guard relevant.isEmpty == false else {
			return 0
		}
		return Double(results.filter(relevant.contains).count) / Double(relevant.count)
	}

	private static func ndcg(results: [String], relevance: [String: Double]) -> Double {
		let dcg = results.enumerated().reduce(0.0) { total, element in
			let (index, id) = element
			let gain = relevance[id] ?? 0
			return total + discountedGain(gain: gain, rank: index + 1)
		}
		let ideal = relevance.values
			.sorted(by: >)
			.prefix(results.count)
			.enumerated()
			.reduce(0.0) { total, element in
				total + discountedGain(gain: element.element, rank: element.offset + 1)
			}
		guard ideal > 0 else {
			return 0
		}
		return dcg / ideal
	}

	private static func discountedGain(gain: Double, rank: Int) -> Double {
		(pow(2, gain) - 1) / log2(Double(rank + 1))
	}
}
