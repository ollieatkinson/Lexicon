import ArgumentParser
import Foundation
import Lexicon

#if MLXSearch
import LexiconSearchMLX
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

	private func embeddingCache(
		at url: URL,
		provider: some Lexicon.SearchEmbeddingProvider,
		rebuild: Bool
	) async throws -> SearchEmbeddingCachePreparation {
		if !rebuild,
		   let cache = try? JSONDecoder().decode(
			Lexicon.SearchEmbeddingCache.self,
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

	private func defaultEmbeddingCacheURL(
		input: URL,
		descriptor: Lexicon.SearchEmbeddingDescriptor
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

	var fileSafeSearchCacheComponent: String {
		map { character in
			character.isLetter || character.isNumber ? String(character) : "-"
		}
		.joined()
	}
}
