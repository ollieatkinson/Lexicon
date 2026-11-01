import Foundation

public enum ONNXSearchTextRole: String, Codable, Hashable, Sendable {
	case query
	case document
}

public struct ONNXSearchModel: Codable, Hashable, Sendable {

	public enum Tokenizer: String, Codable, Hashable, Sendable {
		case wordPiece = "wordpiece"
	}

	public struct Artifact: Codable, Hashable, Sendable {
		public var repository: String
		public var modelPath: String
		public var vocabularyPath: String

		public init(
			repository: String,
			modelPath: String,
			vocabularyPath: String
		) {
			self.repository = repository
			self.modelPath = modelPath
			self.vocabularyPath = vocabularyPath
		}
	}

	public var id: String
	public var revision: String
	public var dimensions: Int
	public var tokenizer: Tokenizer
	public var pooling: ONNXPooling
	public var normalized: Bool
	public var maxLength: Int
	public var lowercased: Bool
	public var queryPrefix: String
	public var documentPrefix: String
	public var inputIDsName: String
	public var attentionMaskName: String
	public var tokenTypeIDsName: String?
	public var outputName: String
	public var artifact: Artifact?

	public init(
		id: String,
		revision: String,
		dimensions: Int,
		tokenizer: Tokenizer = .wordPiece,
		pooling: ONNXPooling = .mean,
		normalized: Bool = true,
		maxLength: Int = 128,
		lowercased: Bool = true,
		queryPrefix: String = "",
		documentPrefix: String = "",
		inputIDsName: String = "input_ids",
		attentionMaskName: String = "attention_mask",
		tokenTypeIDsName: String? = "token_type_ids",
		outputName: String = "last_hidden_state",
		artifact: Artifact? = nil
	) {
		self.id = id
		self.revision = revision
		self.dimensions = dimensions
		self.tokenizer = tokenizer
		self.pooling = pooling
		self.normalized = normalized
		self.maxLength = maxLength
		self.lowercased = lowercased
		self.queryPrefix = queryPrefix
		self.documentPrefix = documentPrefix
		self.inputIDsName = inputIDsName
		self.attentionMaskName = attentionMaskName
		self.tokenTypeIDsName = tokenTypeIDsName
		self.outputName = outputName
		self.artifact = artifact
	}

	public static let allMiniLML6V2 = ONNXSearchModel(
		id: "all-MiniLM-L6-v2",
		revision: "c9745ed1d9f207416be6d2e6f8de32d1f16199bf",
		dimensions: 384,
		maxLength: 256,
		artifact: .init(
			repository: "sentence-transformers/all-MiniLM-L6-v2",
			modelPath: "onnx/model.onnx",
			vocabularyPath: "vocab.txt"
		)
	)

	public static let bgeSmallENV15 = ONNXSearchModel(
		id: "bge-small-en-v1.5",
		revision: "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a",
		dimensions: 384,
		pooling: .cls,
		maxLength: 512,
		queryPrefix: "Represent this sentence for searching relevant passages: ",
		artifact: .init(
			repository: "BAAI/bge-small-en-v1.5",
			modelPath: "onnx/model.onnx",
			vocabularyPath: "vocab.txt"
		)
	)

	public static let gteSmall = ONNXSearchModel(
		id: "gte-small",
		revision: "17e1f347d17fe144873b1201da91788898c639cd",
		dimensions: 384,
		maxLength: 512,
		artifact: .init(
			repository: "thenlper/gte-small",
			modelPath: "onnx/model.onnx",
			vocabularyPath: "vocab.txt"
		)
	)

	public static let e5SmallV2 = ONNXSearchModel(
		id: "e5-small-v2",
		revision: "ffb93f3bd4047442299a41ebb6fa998a38507c52",
		dimensions: 384,
		maxLength: 512,
		queryPrefix: "query: ",
		documentPrefix: "passage: ",
		artifact: .init(
			repository: "intfloat/e5-small-v2",
			modelPath: "onnx/model_O4.onnx",
			vocabularyPath: "vocab.txt"
		)
	)

	public static let presets = [
		allMiniLML6V2,
		bgeSmallENV15,
		gteSmall,
		e5SmallV2,
	]

	public static var `default`: ONNXSearchModel {
		allMiniLML6V2
	}

	public static func preset(named name: String) -> ONNXSearchModel? {
		presets.first { model in
			model.id == name || model.artifact?.repository == name
		}
	}

	public func withRevision(_ revision: String?) -> ONNXSearchModel {
		guard let revision, revision.isEmpty == false else {
			return self
		}
		var copy = self
		copy.revision = revision
		return copy
	}

	public func text(_ text: String, for role: ONNXSearchTextRole) -> String {
		let prefix = role == .query ? queryPrefix : documentPrefix
		return prefix + text
	}

	public func localModelURL(in base: URL) -> URL {
		localDirectory(in: base)
			.appendingPathComponent("model.onnx")
	}

	public func localVocabularyURL(in base: URL) -> URL {
		localDirectory(in: base)
			.appendingPathComponent("vocab.txt")
	}

	public func localManifestURL(in base: URL) -> URL {
		localDirectory(in: base)
			.appendingPathComponent("model.json")
	}

	public func localDirectory(in base: URL) -> URL {
		base.appendingPathComponent(id.fileSafeONNXSearchComponent, isDirectory: true)
	}

	public func artifactURL(path: String) throws -> URL {
		guard let artifact else {
			throw ONNXRuntimeError("ONNX search model \(id) does not declare a downloadable artifact.")
		}
		guard let url = URL(string: "https://huggingface.co/\(artifact.repository)/resolve/\(revision)/\(path)") else {
			throw ONNXRuntimeError("Invalid Hugging Face artifact path: \(path)")
		}
		return url
	}
}

private extension String {
	var fileSafeONNXSearchComponent: String {
		map { character in
			character.isLetter || character.isNumber || character == "-" || character == "_" ? String(character) : "-"
		}
		.joined()
	}
}
