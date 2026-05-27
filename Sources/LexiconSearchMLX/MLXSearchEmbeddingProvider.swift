import Foundation
import Lexicon

#if MLXSearch
import MLX
import MLXEmbedders
import MLXEmbeddersHFAPI
import MLXLMCommon
import Tokenizers

public struct MLXSearchEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	public var descriptor: Lexicon.Search.EmbeddingDescriptor
	private var container: EmbedderModelContainer
	private var queryPrefix: String
	private var documentPrefix: String

	public init(
		modelID: String,
		queryPrefix: String = "search_query: ",
		documentPrefix: String = "search_document: "
	) async throws {
		self.queryPrefix = queryPrefix
		self.documentPrefix = documentPrefix
		self.descriptor = .init(
			provider: "mlx",
			model: modelID,
			tokenizer: "swift-tokenizers/auto",
			normalized: true,
			pooling: "mlx-embedders",
			queryPrefix: queryPrefix,
			documentPrefix: documentPrefix
		)
		let configuration = ModelConfiguration(id: modelID)
		self.container = try await EmbedderModelFactory.shared.loadContainer(
			from: HubClient.default,
			using: LexiconTokenizersLoader(),
			configuration: configuration
		)
	}

	public func embed(_ texts: [String]) async throws -> [[Double]] {
		try await embedDocuments(texts)
	}

	public func embedQuery(_ query: String) async throws -> [Double] {
		guard let vector = try await embedRaw([queryPrefix + query]).first else {
			throw "MLX search did not return a query embedding."
		}
		return vector
	}

	public func embedDocuments(_ texts: [String]) async throws -> [[Double]] {
		try await embedRaw(texts.map { documentPrefix + $0 })
	}

	private func embedRaw(_ texts: [String]) async throws -> [[Double]] {
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
