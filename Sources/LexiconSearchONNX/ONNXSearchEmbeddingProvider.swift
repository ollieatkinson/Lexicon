import Foundation
import Lexicon

#if ONNXSearch
public struct ONNXSearchEmbeddingProvider: Lexicon.SearchEmbeddingProvider {
	public var descriptor: Lexicon.SearchEmbeddingDescriptor

	private var session: ONNXRuntimeSession
	private var tokenizer: WordPieceSearchTokenizer
	private var pooling: ONNXPooling

	public init(
		model: URL,
		vocabulary: URL,
		modelRevision: String = "c9745ed1d9f207416be6d2e6f8de32d1f16199bf",
		runtimeVersion: String? = nil,
		maxLength: Int = 128
	) throws {
		self.session = try ONNXRuntimeSession(model: model)
		self.tokenizer = try WordPieceSearchTokenizer(
			vocabulary: vocabulary,
			revision: modelRevision,
			maxLength: maxLength
		)
		self.pooling = .mean
		self.descriptor = .init(
			provider: "onnxruntime-\(runtimeVersion ?? session.runtimeVersion)",
			model: model.lastPathComponent,
			modelRevision: modelRevision,
			tokenizer: tokenizer.identifier,
			dimensions: 384,
			normalized: true,
			pooling: "mean"
		)
	}

	public func embed(_ texts: [String]) async throws -> [[Double]] {
		let batch = try tokenizer.encode(texts)
		let output = try session.run(batch: batch)
		return try pooling.vectors(from: output, attentionMask: batch.attentionMask)
	}
}
#endif
