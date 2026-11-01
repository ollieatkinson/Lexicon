@testable import LexiconSearchONNX
import XCTest

final class ONNXPoolingTests: XCTestCase {
	func test_invalid_output_shapes_throw_instead_of_trapping() {
		for shape in [[-1, -1], [1, 0, 2], [Int.max, 2], [Int.max, Int.max, 2]] {
			XCTAssertThrowsError(try ONNXPooling.cls.vectors(
				from: ONNXFloatTensor(values: [], shape: shape), attentionMask: []))
		}
	}

	func test_input_shapes_are_checked_before_crossing_the_c_boundary() throws {
		let valid = ONNXTokenBatch(inputIDs: [[1, 2]], attentionMask: [[1, 1]], tokenTypeIDs: [[0, 0]])
		XCTAssertNoThrow(try valid.validate(requiresTokenTypeIDs: true))
		for invalid in [
			ONNXTokenBatch(inputIDs: [], attentionMask: [], tokenTypeIDs: []),
			ONNXTokenBatch(inputIDs: [[]], attentionMask: [[]], tokenTypeIDs: [[]]),
			ONNXTokenBatch(inputIDs: [[1, 2], [1]], attentionMask: [[1, 1], [1]], tokenTypeIDs: []),
			ONNXTokenBatch(inputIDs: [[1, 2]], attentionMask: [[1]], tokenTypeIDs: [[0, 0]]),
			ONNXTokenBatch(inputIDs: [[1, 2]], attentionMask: [[1, 1]], tokenTypeIDs: []),
		] {
			XCTAssertThrowsError(try invalid.validate(requiresTokenTypeIDs: true))
		}
		let withoutTypes = ONNXTokenBatch(inputIDs: [[1, 2]], attentionMask: [[1, 1]], tokenTypeIDs: [])
		XCTAssertNoThrow(try withoutTypes.validate(requiresTokenTypeIDs: false))
	}

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
