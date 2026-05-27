import ArgumentParser
import Foundation
import Lexicon

#if MLXSearch
import MLX
import MLXEmbedders
import MLXEmbeddersHFAPI
import MLXLMCommon
import Tokenizers
#endif

enum SearchEmbeddingProviderSelection: String {
	case auto
	case system
	case mlx
	case none

	init(agentArgument value: String) throws {
		guard let selection = Self(rawValue: value) else {
			throw ValidationError("Unknown embedding provider '\(value)'. Expected auto, system, mlx, or none.")
		}
		self = selection
	}
}

struct SearchEmbeddingCachePreparation {
	var cache: Lexicon.SearchEmbeddingCache
	var url: URL
	var reused: Bool
}

extension Lexicon.SearchIndex {

	func search(
		_ query: String,
		in document: Lexicon.Document,
		input: URL,
		embeddingProvider selection: SearchEmbeddingProviderSelection,
		embeddingModel: String,
		embeddingCache cacheURL: URL?,
		rebuildEmbeddings: Bool
	) async throws -> [Lexicon.SearchResult] {
		guard options.mode == .semantic || options.mode == .hybrid else {
			return try await searchLocally(query, in: document)
		}

		switch selection {
			case .auto:
				#if MLXSearch
					return try await searchWithMLX(
						query,
						input: input,
						document: document,
						modelID: embeddingModel,
						cacheURL: cacheURL,
						rebuildEmbeddings: rebuildEmbeddings
					)
				#else
				return try await searchLocally(query, in: document)
				#endif
			case .system:
				return try await searchLocally(query, in: document)
			case .none:
				return try await searchLocally(query, in: document, queryVector: [])
			case .mlx:
				#if MLXSearch
				return try await searchWithMLX(
					query,
					input: input,
					document: document,
					modelID: embeddingModel,
					cacheURL: cacheURL,
					rebuildEmbeddings: rebuildEmbeddings
				)
				#else
				throw ValidationError("MLX semantic search is not available. Rebuild with --traits MLXSearch.")
				#endif
		}
	}

	private func searchLocally(
		_ query: String,
		in document: Lexicon.Document,
		queryVector: [Double]? = nil
	) async throws -> [Lexicon.SearchResult] {
		if options.scope != .own {
			return try await search(query, in: document, queryVector: queryVector)
		}
		return search(query, queryVector: queryVector)
	}

	#if MLXSearch
	private func searchWithMLX(
		_ query: String,
		input: URL,
		document: Lexicon.Document,
		modelID: String,
		cacheURL: URL?,
		rebuildEmbeddings: Bool
	) async throws -> [Lexicon.SearchResult] {
		let provider = try await MLXSearchEmbeddingProvider(modelID: modelID)
		let index = options.scope == .full ? try await materialized(in: document) : self
		let cacheURL = try cacheURL ?? index.defaultEmbeddingCacheURL(input: input, modelID: modelID)
		let preparation = try await index.embeddingCache(
			at: cacheURL,
			provider: provider,
			rebuild: rebuildEmbeddings
		)
		let queryVector = try await provider.embed(["search_query: \(query)"]).first
		if index.options.scope == .live {
			return try await index.search(
				query,
				in: document,
				embeddingCache: preparation.cache,
				queryVector: queryVector,
				contextEmbeddingProvider: provider
			)
		}
		return index.search(query, embeddingCache: preparation.cache, queryVector: queryVector)
	}

	private func embeddingCache(
		at url: URL,
		provider: MLXSearchEmbeddingProvider,
		rebuild: Bool
	) async throws -> SearchEmbeddingCachePreparation {
		if !rebuild,
		   let cache = try? JSONDecoder().decode(
			Lexicon.SearchEmbeddingCache.self,
			from: Data(contentsOf: url)
		   ),
		   cache.model == provider.identifier,
		   cache.fingerprint == fingerprint
		{
			return .init(cache: cache, url: url, reused: true)
		}

		FileHandle.standardError.write(Data(
			"indexing search embeddings: \(entries.count) entries, model \(provider.identifier)\n".utf8
		))
		let cache = try await embeddingCache(using: provider)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		try encoder.encode(cache).write(to: url)
		return .init(cache: cache, url: url, reused: false)
	}
	#endif

	private func defaultEmbeddingCacheURL(input: URL, modelID: String) throws -> URL {
		let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache", isDirectory: true)
		let model = modelID
			.replacingOccurrences(of: "/", with: "-")
			.replacingOccurrences(of: ":", with: "-")
		let name = "\(input.lastPathComponent).\(fingerprint).\(model).embeddings.json"
		return base
			.appendingPathComponent("Lexicon", isDirectory: true)
			.appendingPathComponent("Search", isDirectory: true)
			.appendingPathComponent(name)
	}
}

#if MLXSearch
struct MLXSearchEmbeddingProvider: Lexicon.SearchEmbeddingProvider {
	var identifier: String
	private var container: EmbedderModelContainer

	init(modelID: String) async throws {
		self.identifier = modelID
		let configuration = ModelConfiguration(id: modelID)
		self.container = try await EmbedderModelFactory.shared.loadContainer(
			from: HubClient.default,
			using: LexiconTokenizersLoader(),
			configuration: configuration
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		await container.perform { context in
			let inputs = texts.map {
				context.tokenizer.encode(text: $0, addSpecialTokens: true)
			}
			let maxLength = inputs.reduce(into: 16) { length, input in
				length = max(length, input.count)
			}
			let padded = stacked(inputs.map { input in
				MLXArray(input + Array(
					repeating: context.tokenizer.eosTokenId ?? 0,
					count: maxLength - input.count
				))
			})
			let mask = padded .!= (context.tokenizer.eosTokenId ?? 0)
			let tokenTypes = MLXArray.zeros(like: padded)
			let embeddings = context.pooling(
				context.model(
					padded,
					positionIds: nil,
					tokenTypeIds: tokenTypes,
					attentionMask: mask
				),
				normalize: true,
				applyLayerNorm: true
			)
			embeddings.eval()
			return embeddings.map { row in
				row.asArray(Float.self).map(Double.init)
			}
		}
	}
}

private struct LexiconTokenizersLoader: TokenizerLoader {
	func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
		let tokenizer = try await AutoTokenizer.from(directory: directory)
		return LexiconTokenizerBridge(tokenizer)
	}
}

private struct LexiconTokenizerBridge: MLXLMCommon.Tokenizer {
	private let upstream: any Tokenizers.Tokenizer

	init(_ upstream: any Tokenizers.Tokenizer) {
		self.upstream = upstream
	}

	func encode(text: String, addSpecialTokens: Bool) -> [Int] {
		(try? upstream.encode(text: text, addSpecialTokens: addSpecialTokens)) ?? []
	}

	func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
		(try? upstream.decode(tokenIds: tokenIds, skipSpecialTokens: skipSpecialTokens)) ?? ""
	}

	func convertTokenToId(_ token: String) -> Int? {
		upstream.convertTokenToId(token)
	}

	func convertIdToToken(_ id: Int) -> String? {
		upstream.convertIdToToken(id)
	}

	var bosToken: String? {
		upstream.bosToken
	}

	var eosToken: String? {
		upstream.eosToken
	}

	var unknownToken: String? {
		upstream.unknownToken
	}

	func applyChatTemplate(
		messages: [[String: any Sendable]],
		tools: [[String: any Sendable]]?,
		additionalContext: [String: any Sendable]?
	) throws -> [Int] {
		do {
			return try upstream.applyChatTemplate(
				messages: messages,
				tools: tools,
				additionalContext: additionalContext
			)
		} catch Tokenizers.TokenizerError.missingChatTemplate {
			throw MLXLMCommon.TokenizerError.missingChatTemplate
		}
	}
}
#endif
