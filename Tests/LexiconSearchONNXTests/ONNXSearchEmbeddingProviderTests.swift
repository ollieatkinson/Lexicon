import Lexicon
import LexiconSearchONNX
import XCTest

#if ONNXSearch
final class ONNXSearchEmbeddingProviderTests: XCTestCase {
	func test_embedder_returns_normalized_vectors() async throws {
		let fixture = try fixtureURLs()
		let provider = try ONNXSearchEmbeddingProvider(
			model: fixture.model,
			vocabulary: fixture.vocabulary
		)
		let vectors = try await provider.embed([
			"late delivery after carrier delay",
			"card issuer rejected transaction",
		])
		XCTAssertEqual(vectors.count, 2)
		XCTAssertEqual(vectors[0].count, 384)
		XCTAssertEqual(vectors[1].count, 384)
		XCTAssertEqual(norm(vectors[0]), 1.0, accuracy: 0.001)
		XCTAssertEqual(norm(vectors[1]), 1.0, accuracy: 0.001)
	}

	func test_provider_can_search_demo_lexicon() async throws {
		let fixture = try fixtureURLs()
		let document = try TaskPaper(Data(contentsOf: fixture.lexicon)).decodeDocument()
		let options = Lexicon.SearchOptions(limit: 5, mode: .semantic, scope: .own)
		let index = Lexicon.SearchIndex(document: document, options: options)
		let provider = try ONNXSearchEmbeddingProvider(
			model: fixture.model,
			vocabulary: fixture.vocabulary
		)
		let cache = try await index.embeddingCache(using: provider)
		let queryVector = try await provider.embed(["search_query: late delivery after carrier delay"]).first
		let results = index.search(
			"late delivery after carrier delay",
			embeddingCache: cache,
			queryVector: queryVector
		)
		XCTAssertFalse(results.isEmpty)
		XCTAssertTrue(results.contains { $0.id.contains("delivery") })
	}

	private func fixtureURLs() throws -> FixtureURLs {
		let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let model = root.appendingPathComponent(".build/onnx-search/all-MiniLM-L6-v2/model.onnx")
		let vocabulary = root.appendingPathComponent(".build/onnx-search/all-MiniLM-L6-v2/vocab.txt")
		let lexicon = root.appendingPathComponent("Examples/search-demo.lexicon").standardizedFileURL
		guard FileManager.default.fileExists(atPath: model.path),
		      FileManager.default.fileExists(atPath: vocabulary.path)
		else {
			throw XCTSkip("Run swift package setup-onnx-search-artifacts before ONNX spike tests.")
		}
		return .init(model: model, vocabulary: vocabulary, lexicon: lexicon)
	}

	private func norm(_ vector: [Double]) -> Double {
		sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
	}
}

private struct FixtureURLs {
	var model: URL
	var vocabulary: URL
	var lexicon: URL
}
#endif
