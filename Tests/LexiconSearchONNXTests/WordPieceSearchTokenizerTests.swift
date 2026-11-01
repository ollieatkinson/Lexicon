import LexiconSearchONNX
import XCTest

final class WordPieceSearchTokenizerTests: XCTestCase {
	func test_ascii_symbols_are_separated_using_bert_punctuation_rules() throws {
		let vocabulary = try temporaryVocabulary(extraTokens: ["c", "+", "$", "5"])
		defer { try? FileManager.default.removeItem(at: vocabulary) }
		let tokenizer = try WordPieceSearchTokenizer(vocabulary: vocabulary, revision: "test", maxLength: 8)
		XCTAssertEqual(try tokenizer.encode(["C++ $5"]).inputIDs, [[2, 10, 11, 11, 12, 13, 3]])
	}

	func test_invalid_sequence_limits_are_rejected_even_after_mutation() throws {
		let vocabulary = try temporaryVocabulary()
		defer { try? FileManager.default.removeItem(at: vocabulary) }
		XCTAssertThrowsError(try WordPieceSearchTokenizer(vocabulary: vocabulary, revision: "test", maxLength: 1))
		var tokenizer = try WordPieceSearchTokenizer(vocabulary: vocabulary, revision: "test", maxLength: 2)
		XCTAssertEqual(try tokenizer.encode(["late delivery"]).inputIDs, [[2, 3]])
		tokenizer.maxLength = Int.min
		XCTAssertThrowsError(try tokenizer.encode(["late delivery"]))
	}

	func test_wordpiece_tokenizer_batches_and_pads_inputs() throws {
		let vocabulary = try temporaryVocabulary()
		let tokenizer = try WordPieceSearchTokenizer(
			vocabulary: vocabulary,
			revision: "test",
			maxLength: 8
		)
		let batch = try tokenizer.encode([
			"late delivery",
			"card issuer rejected transaction",
		])
		XCTAssertEqual(batch.inputIDs.count, 2)
		XCTAssertEqual(batch.inputIDs[0].count, batch.inputIDs[1].count)
		XCTAssertEqual(batch.attentionMask[0].count, batch.inputIDs[0].count)
		XCTAssertEqual(batch.tokenTypeIDs[0], Array(repeating: 0, count: batch.inputIDs[0].count))
	}

	func test_uncased_wordpiece_normalizes_accents_punctuation_and_chinese() throws {
		let vocabulary = try temporaryVocabulary(extraTokens: ["cafe", ",", "世", "界"])
		let tokenizer = try WordPieceSearchTokenizer(
			vocabulary: vocabulary,
			revision: "test",
			maxLength: 8
		)

		let batch = try tokenizer.encode(["Café,世界"])

		XCTAssertEqual(batch.inputIDs, [[2, 10, 11, 12, 13, 3]])
	}

	private func temporaryVocabulary(extraTokens: [String] = []) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("txt")
		let tokens = [
			"[PAD]",
			"[UNK]",
			"[CLS]",
			"[SEP]",
			"late",
			"delivery",
			"card",
			"issuer",
			"rejected",
			"transaction",
		] + extraTokens
		try tokens.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
		return url
	}
}
