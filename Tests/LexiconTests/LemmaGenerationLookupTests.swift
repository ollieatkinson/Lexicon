import Testing

@Suite @LexiconActor
struct LemmaGenerationLookupTests {
	private func document(_ value: String, additionalField: Bool = false) throws -> Lexicon.Document {
		try TaskPaper("""
		shared:
			template:
				title:
				? "\(value)"
		app:
			item:
			+ shared.template
				text:
				= title
			copy:
			= item
		\(additionalField ? "\tnew:" : "")
		""").decodeDocument()
	}

	@Test func absolute_lookup_retains_composed_roots_inheritance_and_alias_placements() throws {
		let lexicon = try Lexicon(document: document("Dorothy"), selectedRoot: "app")
		let item = try #require(lexicon["app.item"])
		for id: Lemma.ID in ["app", "shared", "shared.template.title", "app.item.title", "app.item.text", "app.copy.text"] {
			let resolved = try #require(item[id: id])
			#expect(resolved == lexicon[id])
			#expect(resolved.id == id)
			#expect(resolved.lexiconID == item.lexiconID)
			#expect(resolved.revision == item.revision)
		}
		#expect(item[id: "app.item.text"]?.source.id == "shared.template.title")
		#expect(item[id: "app.copy.text"]?.source.id == "shared.template.title")
		#expect(item[id: "app.typo"] == nil)
		#expect(item[id: "unknown.root"] == nil)
		// Existing string/name lookup remains relative to the handle.
		#expect(item["title"] == item[id: "app.item.title"])
	}

	@Test func lookup_stays_in_its_generation_after_replacement_and_owner_release() throws {
		var owner: Lexicon? = try Lexicon(document: document("Dorothy"), selectedRoot: "app")
		let original = try #require(owner?["app.item"])
		try owner?.replaceDocument(with: document("Witch", additionalField: true), selectedRoot: "shared")
		let current = try #require(owner?["app.item"])
		#expect(original.lexiconID == current.lexiconID)
		#expect(original.revision != current.revision)
		#expect(original[id: "app.item.title"]?.defaultValue == .literal(.string("Dorothy")))
		#expect(current[id: "app.item.title"]?.defaultValue == .literal(.string("Witch")))
		#expect(original[id: "app.new"] == nil)
		#expect(current[id: "app.new"] != nil)
		owner = nil
		#expect(original[id: "app.copy.text"]?.defaultValue == .literal(.string("Dorothy")))
		#expect(current[id: "app.copy.text"]?.defaultValue == .literal(.string("Witch")))
		#expect(original[id: "shared.template.title"]?.revision == original.revision)
	}
}
