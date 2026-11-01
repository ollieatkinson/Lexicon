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

extension Lexicon.Search.Index {

	func search(
		_ query: String,
		in document: Lexicon.Document,
		input: URL,
		embeddingProvider selection: SearchEmbeddingProviderSelection,
		embeddingModel: String?,
		embeddingModelPreset: String?,
		embeddingModelManifest: URL?,
		embeddingVocabulary: URL?,
		embeddingModelRevision: String?,
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
						modelID: embeddingModel ?? .defaultMLXSearchModel,
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
						modelPreset: embeddingModelPreset,
						modelManifest: embeddingModelManifest,
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
					modelID: embeddingModel ?? .defaultMLXSearchModel,
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
					modelPreset: embeddingModelPreset,
					modelManifest: embeddingModelManifest,
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
	#endif

	#if MLXSearch || ONNXSearch
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

	#if ONNXSearch
	private func searchWithONNX(
		_ query: String,
		input: URL,
		document: Lexicon.Document,
		modelPath: String?,
		modelPreset: String?,
		modelManifest: URL?,
		vocabularyURL: URL?,
		modelRevision: String?,
		cacheURL: URL?,
		rebuildEmbeddings: Bool
	) async throws -> [Lexicon.Search.Result] {
		let selection = try ONNXSearchSelection(
			modelPath: modelPath,
			modelPreset: modelPreset,
			modelManifest: modelManifest,
			vocabularyURL: vocabularyURL,
			modelRevision: modelRevision
		)
		let provider = try ONNXSearchEmbeddingProvider(
			model: selection.modelURL,
			vocabulary: selection.vocabularyURL,
			configuration: selection.configuration
		)
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

#if ONNXSearch
private struct ONNXSearchSelection {
	var configuration: ONNXSearchModel
	var modelURL: URL
	var vocabularyURL: URL

	init(
		modelPath: String?,
		modelPreset: String?,
		modelManifest: URL?,
		vocabularyURL: URL?,
		modelRevision: String?
	) throws {
		var configuration = try Self.configuration(
			modelPreset: modelPreset,
			modelManifest: modelManifest,
			modelRevision: modelRevision
		)
		if let modelPath {
			let modelURL = URL(fileURLWithPath: modelPath)
			if modelPreset == nil, modelManifest == nil {
				configuration = .init(
					id: modelURL.onnxSearchModelID,
					revision: modelRevision ?? "local",
					dimensions: configuration.dimensions,
					maxLength: configuration.maxLength
				)
			}
			self.modelURL = modelURL
			self.vocabularyURL = vocabularyURL ?? modelURL
				.deletingLastPathComponent()
				.appendingPathComponent("vocab.txt")
		} else {
			if let modelManifest {
				let directory = modelManifest.deletingLastPathComponent()
				self.modelURL = directory.appendingPathComponent("model.onnx")
				self.vocabularyURL = vocabularyURL ?? directory.appendingPathComponent("vocab.txt")
			} else {
				let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
					.appendingPathComponent(".build", isDirectory: true)
					.appendingPathComponent("onnx-search", isDirectory: true)
				self.modelURL = configuration.localModelURL(in: base)
				self.vocabularyURL = vocabularyURL ?? configuration.localVocabularyURL(in: base)
			}
		}
		self.configuration = configuration
	}

	private static func configuration(
		modelPreset: String?,
		modelManifest: URL?,
		modelRevision: String?
	) throws -> ONNXSearchModel {
		var configuration: ONNXSearchModel
		if let modelManifest {
			configuration = try JSONDecoder().decode(
				ONNXSearchModel.self,
				from: Data(contentsOf: modelManifest)
			)
		} else {
			let preset = modelPreset ?? ONNXSearchModel.default.id
			guard let selected = ONNXSearchModel.preset(named: preset) else {
				throw ValidationError("Unknown ONNX embedding model preset: \(preset)")
			}
			configuration = selected
		}
		return configuration.withRevision(modelRevision)
	}
}
#endif

private extension String {
	static let defaultMLXSearchModel = "TaylorAI/bge-micro-v2"

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

#if ONNXSearch
private extension URL {
	var onnxSearchModelID: String {
		let directory = deletingLastPathComponent().lastPathComponent
		if directory.isEmpty {
			return deletingPathExtension().lastPathComponent
		}
		return directory
	}
}
#endif
