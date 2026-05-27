import ArgumentParser
import Foundation
import Lexicon

#if MLXSearch
import LexiconSearchMLX
#endif
#if ONNXSearch
import LexiconSearchONNX
#endif

enum SearchEmbeddingProviderSelection: String {
	case auto
	case system
	case mlx
	case onnx
	case none

	init(agentArgument value: String) throws {
		guard let selection = Self(rawValue: value) else {
			throw ValidationError("Unknown embedding provider '\(value)'. Expected auto, system, mlx, onnx, or none.")
		}
		self = selection
	}
}

struct SearchEmbeddingCachePreparation {
	var cache: Lexicon.Search.EmbeddingCache
	var url: URL
	var reused: Bool
}

extension Lexicon.Search.Index {

	func search(
		_ query: String,
		in document: Lexicon.Document,
		input: URL,
		embeddingProvider selection: SearchEmbeddingProviderSelection,
		embeddingModel: String,
		embeddingVocabulary: URL?,
		embeddingModelRevision: String,
		embeddingCache cacheURL: URL?,
		rebuildEmbeddings: Bool
	) async throws -> [Lexicon.Search.Result] {
		guard options.mode.contains(.semantic) else {
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
				#if ONNXSearch
					return try await searchWithONNX(
						query,
						input: input,
						document: document,
						modelPath: embeddingModel,
						vocabularyURL: embeddingVocabulary,
						modelRevision: embeddingModelRevision,
						cacheURL: cacheURL,
						rebuildEmbeddings: rebuildEmbeddings
					)
				#else
				return try await searchLocally(query, in: document)
				#endif
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
			case .onnx:
				#if ONNXSearch
				return try await searchWithONNX(
					query,
					input: input,
					document: document,
					modelPath: embeddingModel,
					vocabularyURL: embeddingVocabulary,
					modelRevision: embeddingModelRevision,
					cacheURL: cacheURL,
					rebuildEmbeddings: rebuildEmbeddings
				)
				#else
				throw ValidationError("ONNX semantic search is not available. Rebuild with --traits ONNXSearch.")
				#endif
		}
	}

	private func searchLocally(
		_ query: String,
		in document: Lexicon.Document,
		queryVector: [Double]? = nil
	) async throws -> [Lexicon.Search.Result] {
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
	) async throws -> [Lexicon.Search.Result] {
		let provider = try await MLXSearchEmbeddingProvider(modelID: modelID)
		let index = options.scope == .full ? try await materialized(in: document) : self
		let cacheURL = try cacheURL ?? index.defaultEmbeddingCacheURL(
			input: input,
			descriptor: provider.descriptor
		)
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
	#endif

	#if MLXSearch || ONNXSearch
	private func embeddingCache(
		at url: URL,
		provider: some Lexicon.Search.EmbeddingProvider,
		rebuild: Bool
	) async throws -> SearchEmbeddingCachePreparation {
		if !rebuild,
		   let cache = try? JSONDecoder().decode(
			Lexicon.Search.EmbeddingCache.self,
			from: Data(contentsOf: url)
		   ),
		   cache.descriptor == provider.descriptor,
		   cache.fingerprint == fingerprint
		{
			return .init(cache: cache, url: url, reused: true)
		}

		FileHandle.standardError.write(Data(
			"indexing search embeddings: \(entries.count) entries, model \(provider.descriptor.model)\n".utf8
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

	#if ONNXSearch
	private func searchWithONNX(
		_ query: String,
		input: URL,
		document: Lexicon.Document,
		modelPath: String,
		vocabularyURL: URL?,
		modelRevision: String,
		cacheURL: URL?,
		rebuildEmbeddings: Bool
	) async throws -> [Lexicon.SearchResult] {
		let modelURL = modelPath.onnxModelURL
		let vocabularyURL = vocabularyURL ?? modelURL
			.deletingLastPathComponent()
			.appendingPathComponent("vocab.txt")
		let provider = try ONNXSearchEmbeddingProvider(
			model: modelURL,
			vocabulary: vocabularyURL,
			modelRevision: modelRevision
		)
		let index = options.scope == .full ? try await materialized(in: document) : self
		let cacheURL = try cacheURL ?? index.defaultEmbeddingCacheURL(
			input: input,
			descriptor: provider.descriptor
		)
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
	#endif

	private func defaultEmbeddingCacheURL(
		input: URL,
		descriptor: Lexicon.Search.EmbeddingDescriptor
	) throws -> URL {
		let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache", isDirectory: true)
		let model = descriptor.identifier.fileSafeSearchCacheComponent
		let name = "\(input.lastPathComponent).\(fingerprint).\(model).embeddings.json"
		return base
			.appendingPathComponent("Lexicon", isDirectory: true)
			.appendingPathComponent("Search", isDirectory: true)
			.appendingPathComponent(name)
	}
}

private extension String {
	static let defaultMLXSearchModel = "TaylorAI/bge-micro-v2"

	var onnxModelURL: URL {
		if self == Self.defaultMLXSearchModel {
			return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
				.appendingPathComponent(".build", isDirectory: true)
				.appendingPathComponent("onnx-search", isDirectory: true)
				.appendingPathComponent("all-MiniLM-L6-v2", isDirectory: true)
				.appendingPathComponent("model.onnx")
		}
		return URL(fileURLWithPath: self)
	}

	var fileSafeSearchCacheComponent: String {
		map { character in
			character.isLetter || character.isNumber ? String(character) : "-"
		}
		.joined()
	}
}
