import Foundation
import Lexicon

#if ONNXSearch
public struct ONNXSearchEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	public var descriptor: Lexicon.Search.EmbeddingDescriptor

	private var session: ONNXRuntimeSession
	private var tokenizer: WordPieceSearchTokenizer
	private var pooling: ONNXPooling
	private var configuration: ONNXSearchModel

	public init(
		model: URL,
		vocabulary: URL,
		modelRevision: String = ONNXSearchModel.default.revision,
		runtimeVersion: String? = nil,
		maxLength: Int = 128
	) throws {
		try self.init(
			model: model,
			vocabulary: vocabulary,
			configuration: .init(
				id: model.deletingPathExtension().lastPathComponent,
				revision: modelRevision,
				dimensions: 384,
				maxLength: maxLength
			),
			runtimeVersion: runtimeVersion
		)
	}

	public init(
		model: URL,
		vocabulary: URL,
		configuration: ONNXSearchModel,
		runtimeVersion: String? = nil
	) throws {
		guard configuration.tokenizer == .wordPiece else {
			throw ONNXRuntimeError("Unsupported ONNX tokenizer: \(configuration.tokenizer.rawValue)")
		}
		self.configuration = configuration
		self.session = try ONNXRuntimeSession(model: model)
		self.tokenizer = try WordPieceSearchTokenizer(
			vocabulary: vocabulary,
			revision: configuration.revision,
			maxLength: configuration.maxLength,
			lowercased: configuration.lowercased
		)
		self.pooling = configuration.pooling
		self.descriptor = .init(
			provider: "onnxruntime-\(runtimeVersion ?? session.runtimeVersion)",
			model: configuration.id,
			modelRevision: configuration.revision,
			tokenizer: tokenizer.identifier,
			dimensions: configuration.dimensions,
			normalized: configuration.normalized,
			pooling: configuration.pooling.rawValue,
			queryPrefix: configuration.queryPrefix,
			documentPrefix: configuration.documentPrefix
		)
	}

	public func embed(_ texts: [String]) async throws -> [[Double]] {
		try await embed(texts, as: .document)
	}

	public func embedQuery(_ query: String) async throws -> [Double] {
		guard let vector = try await embed([query], as: .query).first else {
			throw ONNXRuntimeError("ONNX search did not return a query embedding.")
		}
		return vector
	}

	public func embed(_ texts: [String], as role: ONNXSearchTextRole) async throws -> [[Double]] {
		let batch = try tokenizer.encode(texts.map { configuration.text($0, for: role) })
		let output = try session.run(batch: batch, model: configuration)
		return try pooling.vectors(
			from: output,
			attentionMask: batch.attentionMask,
			normalized: configuration.normalized
		)
	}
}
#endif
