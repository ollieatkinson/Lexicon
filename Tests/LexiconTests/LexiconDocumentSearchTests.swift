//
// github.com/screensailor 2026
//

import Foundation
import Hope
@testable import Lexicon

final class LexiconDocumentSearchTests: Hopes {

	func test_token_search_finds_path_segments_and_type_references() throws {
		let document = try Self.fixture()

		let pathResults = document.search("notification authorization status", options: .init(mode: .token))
		hope(pathResults.first?.id) == "root.device.settings.permission.notifications.authorization.status"

		let referenceResults = document.search("session state value", options: .init(mode: .token))
		hope.true(referenceResults.map(\.id).contains("root.preference"))
		hope.true(referenceResults
			.first { $0.id == "root.preference" }?
			.matches
			.contains { $0.field == .type } ?? false)
	}

	func test_lexical_search_finds_metadata_without_synonym_rules() throws {
		let document = try Self.fixture()

		let results = document.search("shown in settings", options: .init(mode: .lexical))
		hope(results.first?.id) == "root.notice"
		hope.true(results.first?.matches.contains { $0.field == .note } ?? false)
	}

	func test_hybrid_search_can_be_scoped_to_a_subtree() throws {
		let document = try Self.fixture()

		let results = document.search(
			"programme device",
			options: .init(root: "root.downloads", mode: .hybrid)
		)

		hope(results.first?.id) == "root.downloads.programme.to.device"
		hope.true(results.allSatisfy { $0.id.hasPrefix("root.downloads") })
	}

	func test_search_mode_can_compose_scoring_lenses() throws {
		let document = try Self.fixture()

		let results = document.search("shown in settings", options: .init(mode: [.lexical, .token]))
		let ids = results.map(\.id)
		let notice = results.first { $0.id == "root.notice" }
		let settings = results.first { $0.id == "root.device.settings" }

		hope.true(ids.contains("root.notice"))
		hope.true(ids.contains("root.device.settings"))
		hope.true((notice?.scores.lexical ?? 0) > 0)
		hope.true((settings?.scores.token ?? 0) > 0)
	}

	func test_live_scope_search_reranks_candidates_with_inherited_children() async throws {
		let document = try Self.inheritedFixture()
		let ownIndex = Lexicon.Search.Index(document: document, options: .init(mode: .token))
		let ownResults = ownIndex.search("entitlement")
		hope.false(ownResults.map(\.id).contains("root.offer"))

		let fullIndex = Lexicon.Search.Index(
			document: document,
			options: .init(mode: .token, scope: .live, bounds: .init(depth: 3))
		)
		let fullResults = try await fullIndex.search("entitlement", in: document)
		let offer = fullResults.first { $0.id == "root.offer" }

		hope(offer?.id) == "root.offer"
		hope.true(offer?.matches.contains { $0.field == .contextChild } ?? false)
	}

	func test_full_scope_materializes_resolved_graph_with_recursion_detection() async throws {
		let document = try Self.recursiveFixture()
		let index = Lexicon.Search.Index(
			document: document,
			options: .init(mode: .token, scope: .full, bounds: .init(depth: .max, budget: 30))
		)

		let materialized = try await index.materialized(in: document)
		let ids = materialized.entries.map(\.id)
		let results = materialized.search("recursive child")

		hope.true(ids.contains("root.item.child"))
		hope.false(ids.contains("root.item.child.child"))
		hope(ids.count) < 30
		hope.true(results.map(\.id).contains("root.item.child"))
	}

	func test_search_demo_lexicon_examples_are_searchable() throws {
		let document = try Self.searchDemoFixture()

		hope(document.search("submit order", options: .init(mode: .hybrid)).first?.id) == "demo.api.order.submit"
		hope(document.search("demo ui product card badge low stock", options: .init(mode: .token)).first?.id) == "demo.ui.product.card.badge.low_stock"
		hope(document.search("card issuer rejected the transaction", options: .init(mode: .lexical)).first?.id) == "demo.api.payment.decline"
	}

	func test_embedding_cache_batches_document_embedding_requests() async throws {
		let document = try Self.largeFixture()
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .semantic))
		let recorder = EmbeddingBatchRecorder()
		let provider = RecordingEmbeddingProvider(recorder: recorder)

		let cache = try await index.embeddingCache(using: provider)

		let expectedBatches = stride(from: 0, to: index.entries.count, by: 32).map {
			min(32, index.entries.count - $0)
		}
		hope(cache.descriptor.provider) == "test"
		hope(cache.descriptor.model) == "embedding-provider"
		hope(cache.vectors.count) == index.entries.count
		let sizes = await recorder.sizes
		hope(sizes) == expectedBatches
	}
}

private extension LexiconDocumentSearchTests {

	static func fixture() throws -> Lexicon.Document {
		try TaskPaper("""
			root:
				type:
					session:
						state:
							value:
					device:
						permission:
							notifications:
								authorization:
				preference:
				+ root.type.session.state.value
				notice:
				> Notification permission state shown in Settings.
				device:
					settings:
						permission:
							notifications:
								authorization:
									status:
									+ root.type.device.permission.notifications.authorization
				downloads:
					programme:
						to:
							device:
			""").decodeDocument()
	}

	static func largeFixture() throws -> Lexicon.Document {
		var source = "root:\n"
		for index in 0..<73 {
			source += "\titem\(index):\n"
			source += "\t+ root.type.value\n"
		}
		return try TaskPaper(source).decodeDocument()
	}

	static func inheritedFixture() throws -> Lexicon.Document {
		try TaskPaper("""
			root:
				type:
					product:
						entitlement:
				offer:
				+ root.type.product
			""").decodeDocument()
	}

	static func recursiveFixture() throws -> Lexicon.Document {
		try TaskPaper("""
			root:
				type:
					branch:
						child:
						+ root.type.branch
						> Recursive child source.
				item:
				+ root.type.branch
			""").decodeDocument()
	}

	static func searchDemoFixture() throws -> Lexicon.Document {
		let url = packageRoot().appendingPathComponent("Examples/search-demo.lexicon")
		return try TaskPaper(Data(contentsOf: url)).decodeDocument()
	}

	static func packageRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}

private actor EmbeddingBatchRecorder {
	private var recordedSizes: [Int] = []

	func record(_ size: Int) {
		recordedSizes.append(size)
	}

	var sizes: [Int] {
		recordedSizes
	}
}

private struct RecordingEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	var recorder: EmbeddingBatchRecorder
	var descriptor: Lexicon.Search.EmbeddingDescriptor {
		.init(
			provider: "test",
			model: "embedding-provider",
			tokenizer: "count",
			dimensions: 1,
			normalized: false,
			pooling: "length"
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		await recorder.record(texts.count)
		return texts.map { [Double($0.count)] }
	}
}
