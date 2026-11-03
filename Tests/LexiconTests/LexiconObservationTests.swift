import Lexicon
import Testing

@LexiconActor
@Suite(.timeLimit(.minutes(1)))
struct LexiconObservationTests {
	private func document(_ value: String) throws -> Lexicon.Document {
		try TaskPaper("""
		shared:
			template:
				title:
				? "\(value)"
		app:
			item:
			+ shared.template
		""").decodeDocument()
	}

	@Test func observation_publishes_complete_generations_and_keeps_retained_handles_frozen() async throws {
		let lexicon = try Lexicon(document: document("Old"), selectedRoot: "app")
		var values = lexicon.observe().makeAsyncIterator()
		let original = try #require(await values.next())
		#expect(original == lexicon.root)
		#expect(original[id: "app.item.title"]?.defaultValue == .literal(.string("Old")))

		try lexicon.replaceDocument(with: document("New"), selectedRoot: "shared")
		let current = try #require(await values.next())
		#expect(current == lexicon.root)
		#expect(current.lexiconID == lexicon.identity)
		#expect(current.revision == lexicon.revision)
		#expect(current.revision > original.revision)
		#expect(current.id == "shared")
		#expect(current[id: "app.item.title"]?.defaultValue == .literal(.string("New")))
		#expect(original[id: "app.item.title"]?.defaultValue == .literal(.string("Old")))

		try lexicon.selectRoot("app")
		let selection = try #require(await values.next())
		#expect(selection.id == "app")
		#expect(selection.revision == current.revision)
		#expect(selection[id: "shared.template.title"] == current[id: "shared.template.title"])

		#if EDITOR
		_ = try lexicon.addChild(named: "added", to: lexicon.root)
		let edited = try #require(await values.next())
		#expect(edited == lexicon.root)
		#expect(edited[id: "app.added"] != nil)
		#expect(selection[id: "app.added"] == nil)
		#endif
	}

	@Test func rejected_edits_and_unchanged_selection_do_not_publish_and_slow_consumers_keep_only_latest() async throws {
		var lexicon: Lexicon? = try Lexicon(document: document("Initial"), selectedRoot: "app")
		var values = try #require(lexicon).observe().makeAsyncIterator()
		_ = try #require(await values.next())
		try lexicon?.replaceDocument(with: document("Intermediate"), selectedRoot: "shared")
		try lexicon?.replaceDocument(with: document("Latest"), selectedRoot: "app")
		let latest = try #require(await values.next())
		#expect(latest == lexicon?.root)
		#expect(latest[id: "app.item.title"]?.defaultValue == .literal(.string("Latest")))
		let rejected = try document("Rejected")
		#expect(throws: LexiconError.self) {
			try lexicon?.replaceDocument(with: rejected, selectedRoot: "missing")
		}
		#expect(throws: LexiconError.self) { try lexicon?.selectRoot("missing") }
		try lexicon?.selectRoot("app")
		weak let released = lexicon
		lexicon = nil
		#expect(released == nil)
		// No phantom failed/no-op update remains buffered after owner teardown.
		#expect(await values.next() == nil)
		#expect(latest[id: "app.item.title"]?.defaultValue == .literal(.string("Latest")))
	}

	@Test func cancelling_one_observer_leaves_the_other_and_lexicon_usable() async throws {
		let lexicon = try Lexicon(document: document("Old"), selectedRoot: "app")
		let first = lexicon.observe()
		var second = lexicon.observe().makeAsyncIterator()
		_ = try #require(await second.next())
		let consumer = Task { @concurrent in
			for await _ in first {}
		}
		consumer.cancel()
		await consumer.value
		try lexicon.replaceDocument(with: document("New"), selectedRoot: "app")
		let current = try #require(await second.next())
		#expect(current == lexicon.root)
		#expect(current[id: "app.item.title"]?.defaultValue == .literal(.string("New")))
	}
}
