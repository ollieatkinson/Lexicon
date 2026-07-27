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

extension Lexicon.Search.Index {

	func search(
		_ query: String,
		in document: Lexicon.Document,
		input: URL,
		embeddingProvider selection: SearchEmbeddingProviderSelection,
		embeddingModel: String,
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
		let cache = try await index.embeddingCache(
			at: cacheURL,
			provider: provider,
			rebuild: rebuildEmbeddings
		)
		return try await index.search(
			query,
			in: document,
			embeddingCache: cache,
			contextEmbeddingProvider: provider
		)
	}

	private func embeddingCache(
		at url: URL,
		provider: some Lexicon.Search.EmbeddingProvider,
		rebuild: Bool
	) async throws -> Lexicon.Search.EmbeddingCache {
		if !rebuild,
		   let cache = try? JSONDecoder().decode(
			Lexicon.Search.EmbeddingCache.self,
			from: Data(contentsOf: url)
		   ),
		   isUsable(cache, for: provider)
		{
			return cache
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
		try encoder.encode(cache).write(to: url, options: .atomic)
		return cache
	}

	private func isUsable(
		_ cache: Lexicon.Search.EmbeddingCache,
		for provider: some Lexicon.Search.EmbeddingProvider
	) -> Bool {
		guard
			cache.version == Lexicon.Search.EmbeddingCache.currentVersion,
			cache.descriptor == provider.descriptor,
			cache.fingerprint == fingerprint,
			Set(cache.vectors.keys) == Set(entries.map(\.id))
		else {
			return false
		}
		if let dimensions = provider.descriptor.dimensions, dimensions <= 0 {
			return false
		}

		var observedDimensions: Int?
		for vector in cache.vectors.values {
			guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else {
				return false
			}
			if let dimensions = provider.descriptor.dimensions {
				guard vector.count == dimensions else {
					return false
				}
			} else if let observedDimensions {
				guard vector.count == observedDimensions else {
					return false
				}
			} else {
				observedDimensions = vector.count
			}
		}
		return true
	}
	#endif

	private func defaultEmbeddingCacheURL(
		input: URL,
		descriptor: Lexicon.Search.EmbeddingDescriptor
	) throws -> URL {
		let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache", isDirectory: true)
		let model = descriptor.identifier.searchCacheFileComponent
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

	var searchCacheFileComponent: String {
		let safe = fileSafeSearchCacheComponent
		let prefix = safe.prefix(80)
		return "\(prefix)-\(fnv1a64Hex)"
	}

	var fnv1a64Hex: String {
		var hash: UInt64 = 0xcbf29ce484222325
		for byte in utf8 {
			hash ^= UInt64(byte)
			hash &*= 0x100000001b3
		}
		return String(hash, radix: 16)
	}
}
