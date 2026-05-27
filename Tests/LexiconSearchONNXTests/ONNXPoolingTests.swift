import LexiconSearchONNX
import XCTest

final class ONNXPoolingTests: XCTestCase {
	func test_mean_pooling_uses_attention_mask() throws {
		let tensor = ONNXFloatTensor(
			values: [
				1, 1,
				3, 3,
				9, 9,
			],
			shape: [1, 3, 2]
		)

		let vectors = try ONNXPooling.mean.vectors(
			from: tensor,
			attentionMask: [[1, 1, 0]],
			normalized: false
		)

		XCTAssertEqual(vectors, [[2, 2]])
	}

	func test_cls_pooling_uses_first_token() throws {
		let tensor = ONNXFloatTensor(
			values: [
				1, 2,
				3, 4,
			],
			shape: [1, 2, 2]
		)

		let vectors = try ONNXPooling.cls.vectors(
			from: tensor,
			attentionMask: [[1, 1]],
			normalized: false
		)

		XCTAssertEqual(vectors, [[1, 2]])
	}

	func test_last_token_pooling_uses_last_unmasked_token() throws {
		let tensor = ONNXFloatTensor(
			values: [
				1, 2,
				3, 4,
				5, 6,
			],
			shape: [1, 3, 2]
		)

		let vectors = try ONNXPooling.lastToken.vectors(
			from: tensor,
			attentionMask: [[1, 1, 0]],
			normalized: false
		)

		XCTAssertEqual(vectors, [[3, 4]])
	}
}
