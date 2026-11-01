import LexiconSearchONNX
import XCTest

final class ONNXSearchModelTests: XCTestCase {
	func test_default_model_is_a_downloadable_preset() throws {
		let model = try XCTUnwrap(ONNXSearchModel.preset(named: "all-MiniLM-L6-v2"))
		XCTAssertEqual(model.artifact?.repository, "sentence-transformers/all-MiniLM-L6-v2")
		XCTAssertEqual(model.revision, "c9745ed1d9f207416be6d2e6f8de32d1f16199bf")
		XCTAssertEqual(model.dimensions, 384)
		XCTAssertEqual(model.pooling, .mean)
		XCTAssertEqual(model.text("refund status", for: .query), "refund status")
		XCTAssertEqual(
			model.localModelURL(in: URL(fileURLWithPath: "/tmp/onnx-search")).path,
			"/tmp/onnx-search/all-MiniLM-L6-v2/model.onnx"
		)
	}

	func test_registry_includes_measured_candidate_models() throws {
		let ids = ONNXSearchModel.presets.map(\.id)

		XCTAssertEqual(ids, [
			"all-MiniLM-L6-v2",
			"bge-small-en-v1.5",
			"gte-small",
			"e5-small-v2",
		])
		XCTAssertEqual(ONNXSearchModel.bgeSmallENV15.pooling, .cls)
		XCTAssertEqual(
			ONNXSearchModel.e5SmallV2.text("refund status", for: .query),
			"query: refund status"
		)
		XCTAssertEqual(
			ONNXSearchModel.e5SmallV2.text("refund policy", for: .document),
			"passage: refund policy"
		)
	}

	func test_model_manifest_round_trips() throws {
		let model = ONNXSearchModel.default.withRevision("test-revision")
		let data = try JSONEncoder().encode(model)
		let decoded = try JSONDecoder().decode(ONNXSearchModel.self, from: data)
		XCTAssertEqual(decoded, model)
	}
}
