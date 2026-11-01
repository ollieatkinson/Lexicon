import Testing

@Suite @LexiconActor
struct LemmaGenerationLookupTests {
	@Test func warmed_resolution_keeps_inherited_placements_aliases_and_revisions_independent() throws {
		func document(_ value: String, extra: Bool = false) throws -> Lexicon.Document {
			try TaskPaper("""
			shared:
				template:
					title:
					? "\(value)"
			\(extra ? "\t\tadded:" : "")
			app:
				one:
				+ shared.template
				two:
				+ shared.template
				alias:
				= one
			""").decodeDocument()
		}
		var owner: Lexicon? = try Lexicon(document: document("Dorothy"), selectedRoot: "app")
		let old = try #require(owner?.root)
		func check(_ root: Lemma, _ value: String, hasExtra: Bool) throws {
			for _ in 0..<4 {
				for id: Lemma.ID in ["app.one.title", "app.two.title", "app.alias.title"] {
					let field = try #require(root[id: id])
					#expect(field.id == id && field.source.id == "shared.template.title")
					#expect(field.defaultValue == .literal(.string(value)))
					#expect((root[id: id.parent!.appending("added" as Lemma.Name)] != nil) == hasExtra)
				}
			}
		}
		try check(old, "Dorothy", hasExtra: false)
		try owner?.replaceDocument(with: document("Witch", extra: true), selectedRoot: "shared")
		let current = try #require(owner?.root)
		owner = nil
		try check(current, "Witch", hasExtra: true)
		try check(old, "Dorothy", hasExtra: false)
	}

	@Test func repeated_type_queries_preserve_alias_placements_and_generation_changes() throws {
		func document(_ role: String) throws -> Lexicon.Document {
			try TaskPaper("""
			shared:
				collection:
				ordinary:
				template:
				+ shared.\(role)
					field:
					+ shared.ordinary
			app:
				item:
				+ shared.template
				alias:
				= item
			""").decodeDocument()
		}
		var owner: Lexicon? = try Lexicon(document: document("collection"), selectedRoot: "app")
		let original = try #require(owner?.root)
		let collection = try #require(original[id: "shared.collection"])
		let ordinary = try #require(original[id: "shared.ordinary"])
		func check(_ root: Lemma, isCollection: Bool) throws {
			for _ in 0..<3 {
				for id: Lemma.ID in ["app.item", "app.alias"] {
					let item = try #require(root[id: id])
					#expect(item.is(collection) == isCollection)
					#expect(item.is(ordinary) == !isCollection)
				}
				for id: Lemma.ID in ["app.item.field", "app.alias.field"] {
					let field = try #require(root[id: id])
					#expect(field.is(ordinary))
					#expect(!field.is(collection))
				}
			}
		}
		try check(original, isCollection: true)
		try owner?.replaceDocument(with: document("ordinary"), selectedRoot: "shared")
		let current = try #require(owner?.root)
		owner = nil
		try check(current, isCollection: false)
		try check(original, isCollection: true)
	}

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
