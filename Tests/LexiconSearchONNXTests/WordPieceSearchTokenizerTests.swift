import LexiconSearchONNX
import XCTest

final class WordPieceSearchTokenizerTests: XCTestCase {
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
