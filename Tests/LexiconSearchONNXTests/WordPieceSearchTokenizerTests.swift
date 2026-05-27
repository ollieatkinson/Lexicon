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

	private func temporaryVocabulary() throws -> URL {
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
		]
		try tokens.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
		return url
	}
}
