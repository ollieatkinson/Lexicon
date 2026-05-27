import Foundation

public struct WordPieceSearchTokenizer: Sendable {
	public var identifier: String
	public var maxLength: Int

	private var vocabulary: [String: Int64]
	private var lowercased: Bool
	private var unknownTokenID: Int64
	private var clsTokenID: Int64
	private var sepTokenID: Int64
	private var padTokenID: Int64

	public init(
		vocabulary url: URL,
		revision: String,
		maxLength: Int = 128,
		lowercased: Bool = true
	) throws {
		let contents = try String(contentsOf: url, encoding: .utf8)
		var vocabulary: [String: Int64] = [:]
		for (offset, token) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
			vocabulary[String(token)] = Int64(offset)
		}
		guard
			let unknownTokenID = vocabulary["[UNK]"],
			let clsTokenID = vocabulary["[CLS]"],
			let sepTokenID = vocabulary["[SEP]"],
			let padTokenID = vocabulary["[PAD]"]
		else {
			throw ONNXRuntimeError("Vocabulary is missing required BERT special tokens.")
		}
		self.identifier = "wordpiece:\(url.lastPathComponent):\(revision):max-\(maxLength):\(lowercased ? "lower" : "case")"
		self.maxLength = maxLength
		self.vocabulary = vocabulary
		self.lowercased = lowercased
		self.unknownTokenID = unknownTokenID
		self.clsTokenID = clsTokenID
		self.sepTokenID = sepTokenID
		self.padTokenID = padTokenID
	}

	public func encode(_ texts: [String]) throws -> ONNXTokenBatch {
		let encoded = texts.map(encodeSingle)
		let sequenceLength = max(1, encoded.map(\.count).max() ?? 0)
		let padded = encoded.map { ids in
			ids + Array(repeating: padTokenID, count: sequenceLength - ids.count)
		}
		let attentionMask = encoded.map { ids in
			Array(repeating: Int64(1), count: ids.count)
				+ Array(repeating: Int64(0), count: sequenceLength - ids.count)
		}
		let tokenTypeIDs = encoded.map { ids in
			Array(repeating: Int64(0), count: sequenceLength)
		}
		return .init(
			inputIDs: padded,
			attentionMask: attentionMask,
			tokenTypeIDs: tokenTypeIDs
		)
	}

	private func encodeSingle(_ text: String) -> [Int64] {
		var ids = [clsTokenID]
		let pieces = basicTokens(in: text).flatMap(wordPieces)
		let limit = max(0, maxLength - 2)
		ids.append(contentsOf: pieces.prefix(limit).map { vocabulary[$0] ?? unknownTokenID })
		ids.append(sepTokenID)
		return ids
	}

	private func basicTokens(in text: String) -> [String] {
		var tokens: [String] = []
		var current = ""
		let normalized = lowercased ? text.lowercased() : text
		for scalar in normalized.unicodeScalars {
			if CharacterSet.whitespacesAndNewlines.contains(scalar) {
				append(&current, to: &tokens)
			} else if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
				append(&current, to: &tokens)
				tokens.append(String(scalar))
			} else {
				current.unicodeScalars.append(scalar)
			}
		}
		append(&current, to: &tokens)
		return tokens
	}

	private func append(_ current: inout String, to tokens: inout [String]) {
		guard !current.isEmpty else {
			return
		}
		tokens.append(current)
		current.removeAll(keepingCapacity: true)
	}

	private func wordPieces(for token: String) -> [String] {
		guard !token.isEmpty else {
			return []
		}
		if vocabulary[token] != nil {
			return [token]
		}
		let characters = Array(token)
		var start = characters.startIndex
		var pieces: [String] = []
		while start < characters.endIndex {
			var end = characters.endIndex
			var match: String?
			while start < end {
				let value = String(characters[start..<end])
				let candidate = start == characters.startIndex ? value : "##\(value)"
				if vocabulary[candidate] != nil {
					match = candidate
					break
				}
				end = characters.index(before: end)
			}
			guard let match else {
				return ["[UNK]"]
			}
			pieces.append(match)
			start = end
		}
		return pieces
	}
}
