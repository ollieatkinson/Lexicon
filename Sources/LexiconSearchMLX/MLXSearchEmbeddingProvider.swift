import Foundation
import Lexicon

#if MLXSearch
import MLX
import MLXEmbedders
import MLXEmbeddersHFAPI
import MLXLMCommon
import Synchronization
import Tokenizers

public enum MLXSearchEmbeddingProviderError: Error, Hashable, Sendable, CustomStringConvertible {
	case tokenizerEncodingFailed(text: String, reason: String)
	case tokenizerDecodingFailed(tokenIDs: [Int], reason: String)

	public var description: String {
		switch self {
		case .tokenizerEncodingFailed(let text, let reason):
			"MLX tokenizer could not encode \(String(reflecting: text)): \(reason)"
		case .tokenizerDecodingFailed(let tokenIDs, let reason):
			"MLX tokenizer could not decode \(tokenIDs): \(reason)"
		}
	}
}

public struct MLXSearchEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	public var descriptor: Lexicon.Search.EmbeddingDescriptor
	private var container: EmbedderModelContainer
	private let tokenizerFailures: TokenizerFailureRecorder

	public init(modelID: String) async throws {
		self.descriptor = .init(
			provider: "mlx",
			model: modelID,
			tokenizer: "swift-tokenizers/auto",
			normalized: true,
			pooling: "mlx-embedders"
		)
		let configuration = ModelConfiguration(id: modelID)
		let tokenizerFailures = TokenizerFailureRecorder()
		self.tokenizerFailures = tokenizerFailures
		self.container = try await EmbedderModelFactory.shared.loadContainer(
			from: HubClient.default,
			using: LexiconTokenizersLoader(failures: tokenizerFailures),
			configuration: configuration
		)
	}

	public func embed(_ texts: [String]) async throws -> [[Double]] {
		guard !texts.isEmpty else {
			return []
		}
		return try await container.perform { context in
			tokenizerFailures.reset()
			let inputs = texts.map {
				context.tokenizer.encode(text: $0, addSpecialTokens: true)
			}
			if let failure = tokenizerFailures.take() {
				throw failure
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
	let failures: TokenizerFailureRecorder

	func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
		let tokenizer = try await AutoTokenizer.from(directory: directory)
		return LexiconTokenizerBridge(tokenizer, failures: failures)
	}
}

private struct LexiconTokenizerBridge: MLXLMCommon.Tokenizer {
	private let upstream: any Tokenizers.Tokenizer
	private let failures: TokenizerFailureRecorder

	init(_ upstream: any Tokenizers.Tokenizer, failures: TokenizerFailureRecorder) {
		self.upstream = upstream
		self.failures = failures
	}

	func encode(text: String, addSpecialTokens: Bool) -> [Int] {
		do {
			return try upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
		} catch {
			failures.record(.tokenizerEncodingFailed(text: text, reason: String(describing: error)))
			return []
		}
	}

	func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
		do {
			return try upstream.decode(tokenIds: tokenIds, skipSpecialTokens: skipSpecialTokens)
		} catch {
			failures.record(.tokenizerDecodingFailed(
				tokenIDs: tokenIds,
				reason: String(describing: error)
			))
			return ""
		}
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
		} catch {
			if error == .missingChatTemplate {
				throw MLXLMCommon.TokenizerError.missingChatTemplate
			}
			throw error
		}
	}
}

private final class TokenizerFailureRecorder: Sendable {
	private let failure = Mutex<MLXSearchEmbeddingProviderError?>(nil)

	func reset() {
		failure.withLock { $0 = nil }
	}

	func record(_ error: MLXSearchEmbeddingProviderError) {
		failure.withLock { failure in
			if failure == nil {
				failure = error
			}
		}
	}

	func take() -> MLXSearchEmbeddingProviderError? {
		failure.withLock { failure in
			defer { failure = nil }
			return failure
		}
	}
}
#endif
