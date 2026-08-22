//
// github.com/screensailor 2026
//

import Testing
import Foundation
@testable import Lexicon

@Suite

struct LexiconDocumentSearchTests {

	@Test
	func test_token_search_finds_path_segments_and_type_references() throws {
		let document = try Self.fixture()

		let pathResults = document.search("notification authorization status", options: .init(mode: .token))
		#expect(pathResults.first?.id == "root.device.settings.permission.notifications.authorization.status")

		let referenceResults = document.search("session state value", options: .init(mode: .token))
		#expect(referenceResults.map(\.id).contains("root.preference"))
		#expect(referenceResults
			.first { $0.id == "root.preference" }?
			.matches
			.contains { $0.field == .type } ?? false)
	}

	@Test
	func test_lexical_search_finds_metadata_without_synonym_rules() throws {
		let document = try Self.fixture()

		let results = document.search("shown in settings", options: .init(mode: .lexical))
		#expect(results.first?.id == "root.notice")
		#expect(results.first?.matches.contains { $0.field == .note } ?? false)
	}

	@Test
	func test_hybrid_search_can_be_scoped_to_a_subtree() throws {
		let document = try Self.fixture()

		let results = document.search(
			"programme device",
			options: .init(root: "root.downloads", mode: .hybrid)
		)

		#expect(results.first?.id == "root.downloads.programme.to.device")
		#expect(results.allSatisfy { $0.id.isInLineage(of: "root.downloads") })
	}

	#if canImport(NaturalLanguage)
	@Test
	func test_repeated_hybrid_searches_on_one_index_are_stable() async throws {
		let document = try Self.searchDemoFixture()
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .hybrid))
		let queries = [
			"submit order",
			"demo ui product card badge low stock",
			"card issuer rejected the transaction",
		]
		let expected = queries.map { index.search($0).map(\.id) }

		await withTaskGroup(of: (Int, [Lemma.ID]).self) { group in
			for iteration in 0..<24 {
				group.addTask {
					let queryIndex = iteration % queries.count
					return (queryIndex, index.search(queries[queryIndex]).map(\.id))
				}
			}

			for await (queryIndex, ids) in group {
				#expect(ids == expected[queryIndex])
			}
		}
	}
	#endif

	@Test
	func test_search_mode_can_compose_scoring_lenses() throws {
		let document = try Self.fixture()

		let results = document.search("shown in settings", options: .init(mode: [.lexical, .token]))
		let ids = results.map(\.id)
		let notice = results.first { $0.id == "root.notice" }
		let settings = results.first { $0.id == "root.device.settings" }

		#expect(ids.contains("root.notice"))
		#expect(ids.contains("root.device.settings"))
		#expect((notice?.scores.lexical ?? 0) > 0)
		#expect((settings?.scores.token ?? 0) > 0)
	}

	@Test
	func test_live_scope_search_reranks_candidates_with_inherited_children() async throws {
		let document = try Self.inheritedFixture()
		let ownIndex = Lexicon.Search.Index(document: document, options: .init(mode: .token))
		let ownResults = ownIndex.search("entitlement")
		#expect(!(ownResults.map(\.id).contains("root.offer")))

		let fullIndex = Lexicon.Search.Index(
			document: document,
			options: .init(mode: .token, scope: .live, bounds: .init(depth: 3))
		)
		let fullResults = try await fullIndex.search("entitlement", in: document)
		let offer = fullResults.first { $0.id == "root.offer" }

		#expect(offer?.id == "root.offer")
		#expect(offer?.matches.contains { $0.field == .contextChild } ?? false)
	}

	@Test
	func test_full_scope_materializes_resolved_graph_with_recursion_detection() async throws {
		let document = try Self.recursiveFixture()
		let index = Lexicon.Search.Index(
			document: document,
			options: .init(mode: .token, scope: .full, bounds: .init(depth: .max, budget: 30))
		)

		let materialized = try await index.materialized(in: document)
		let ids = materialized.entries.map(\.id)
		let results = materialized.search("recursive child")

		#expect(ids.contains("root.item.child"))
		#expect(!(ids.contains("root.item.child.child")))
		#expect(ids.count < 30)
		#expect(results.map(\.id).contains("root.item.child"))
	}

	@Test
	func test_search_demo_lexicon_examples_are_searchable() throws {
		let document = try Self.searchDemoFixture()

		#expect(document.search("submit order", options: .init(mode: .hybrid)).first?.id == "demo.api.order.submit")
		#expect(document.search("demo ui product card badge low stock", options: .init(mode: .token)).first?.id == "demo.ui.product.card.badge.low_stock")
		#expect(document.search("card issuer rejected the transaction", options: .init(mode: .lexical)).first?.id == "demo.api.payment.decline")
	}

	@Test
	func test_embedding_cache_batches_document_embedding_requests() async throws {
		let document = try Self.largeFixture()
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .semantic))
		let recorder = EmbeddingBatchRecorder()
		let provider = RecordingEmbeddingProvider(recorder: recorder)

		let cache = try await index.embeddingCache(using: provider)

		let expectedBatches = stride(from: 0, to: index.entries.count, by: 32).map {
			min(32, index.entries.count - $0)
		}
		#expect(cache.descriptor.provider == "test")
		#expect(cache.descriptor.model == "embedding-provider")
		#expect(cache.vectors.count == index.entries.count)
		let sizes = await recorder.sizes
		#expect(sizes == expectedBatches)
	}

	@Test
	func test_provider_backed_semantic_search_embeds_query_for_live_and_full_scope() async throws {
		let document = try Self.providerBackedSemanticFixture()
		let provider = KeywordEmbeddingProvider()

		for scope in [Lexicon.Search.Scope.live, .full] {
			let index = Lexicon.Search.Index(
				document: document,
				options: .init(
					limit: 1,
					mode: .semantic,
					scope: scope,
					semanticThreshold: 0.9
				)
			)

			let results = try await index.search(
				"provider query",
				in: document,
				contextEmbeddingProvider: provider
			)

			#expect(results.first?.id == "root.target")
			#expect((results.first?.scores.semantic ?? 0) > 0.99)
		}
	}

	@Test
	func test_embedding_provider_vector_count_mismatch_throws() async throws {
		let document = try Self.providerBackedSemanticFixture()
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .semantic))
		let provider = ShortEmbeddingProvider()
		var message: String?

		do {
			_ = try await index.embeddingCache(using: provider)
		} catch {
			message = "\(error)"
		}

		#expect(message?.contains("Embedding provider returned") ?? false)
	}

	@Test
	func test_embedding_descriptor_identifier_is_derived_from_current_fields() throws {
		var descriptor = Lexicon.Search.EmbeddingDescriptor(
			provider: "test",
			model: "first",
			modelRevision: "one",
			tokenizer: "wordpiece",
			dimensions: 384,
			normalized: true,
			pooling: "mean"
		)
		let firstIdentifier = descriptor.identifier

		descriptor.model = "second"
		descriptor.modelRevision = "two"

		#expect(!(descriptor.identifier == firstIdentifier))
		#expect(descriptor.identifier.contains("second"))
		#expect(descriptor.identifier.contains("two"))

		let decoded = try JSONDecoder().decode(
			Lexicon.Search.EmbeddingDescriptor.self,
			from: JSONEncoder().encode(descriptor)
		)
		#expect(decoded.identifier == descriptor.identifier)
	}

	@Test
	func test_legacy_embedding_descriptor_decodes_with_legacy_prefixes() throws {
		let data = Data("""
			{
				"provider": "test",
				"model": "legacy",
				"tokenizer": "test",
				"normalized": true,
				"pooling": "mean"
			}
			""".utf8)

		let descriptor = try JSONDecoder().decode(
			Lexicon.Search.EmbeddingDescriptor.self,
			from: data
		)

		#expect(descriptor.queryPrefix == "search_query: ")
		#expect(descriptor.documentPrefix == "search_document: ")
	}

	@Test
	func test_default_embedding_provider_methods_apply_descriptor_prefixes() async throws {
		let recorder = EmbeddingTextRecorder()
		let provider = PrefixRecordingEmbeddingProvider(recorder: recorder)

		_ = try await provider.embedQuery("refund status")
		_ = try await provider.embedDocuments(["refund policy"])

		let batches = await recorder.batches
		#expect(batches == [
			["query: refund status"],
			["passage: refund policy"],
		])
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

	static func providerBackedSemanticFixture() throws -> Lexicon.Document {
		try TaskPaper("""
			root:
				target:
				> Semantic provider destination.
				other:
				> Unrelated document.
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

private actor EmbeddingTextRecorder {
	private var recordedBatches: [[String]] = []

	func record(_ texts: [String]) {
		recordedBatches.append(texts)
	}

	var batches: [[String]] {
		recordedBatches
	}
}

private struct PrefixRecordingEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	var recorder: EmbeddingTextRecorder
	var descriptor: Lexicon.Search.EmbeddingDescriptor {
		.init(
			provider: "test",
			model: "prefixed",
			tokenizer: "test",
			dimensions: 1,
			normalized: false,
			pooling: "test",
			queryPrefix: "query: ",
			documentPrefix: "passage: "
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		await recorder.record(texts)
		return Array(repeating: [1], count: texts.count)
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

private struct KeywordEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	var descriptor: Lexicon.Search.EmbeddingDescriptor {
		.init(
			provider: "test",
			model: "keyword",
			tokenizer: "test",
			dimensions: 2,
			normalized: true,
			pooling: "test"
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		texts.map { text in
			if text.localizedCaseInsensitiveContains("provider query") ||
				text.localizedCaseInsensitiveContains("semantic provider destination")
			{
				return [1, 0]
			}
			return [0, 1]
		}
	}
}

private struct ShortEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	var descriptor: Lexicon.Search.EmbeddingDescriptor {
		.init(
			provider: "test",
			model: "short",
			tokenizer: "test",
			dimensions: 1,
			normalized: false,
			pooling: "test"
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		Array(repeating: [0], count: max(0, texts.count - 1))
	}
}
