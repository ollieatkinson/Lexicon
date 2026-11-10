import Testing

@Suite @LexiconActor
struct LemmaDependencyTraversalTests {
	private func document(depth: Int, baseDefault: String? = nil) throws -> Lexicon.Document {
		var lines = ["probe:", "\tbase:"]
		if let baseDefault { lines.append("\t? \"\(baseDefault)\"") }
		for level in 0...depth {
			let parents = level == 0 ? ["probe.base"] : ["probe.left\(level - 1)", "probe.right\(level - 1)"]
			for side in ["left", "right"] {
				lines.append("\t\(side)\(level):")
				lines += parents.map { "\t+ \($0)" }
			}
		}
		lines += ["\tz_first:", "\t? \"first\"", "\tzz_second:", "\t? \"second\"",
			"\tempty:", "\t+ probe.left\(depth)", "\t+ probe.right\(depth)",
			"\tvalue:", "\t+ probe.left\(depth)", "\t+ probe.right\(depth)",
			"\t+ probe.z_first", "\t+ probe.zz_second", "\talias:", "\t= empty"]
		return try TaskPaper(lines.joined(separator: "\n")).decodeDocument()
	}

	@Test func shared_dependency_branches_keep_types_and_the_first_reachable_default() throws {
		let owner = try Lexicon(document: document(depth: 6), selectedRoot: "probe")
		let empty = try #require(owner.root["empty"])
		let value = try #require(owner.root["value"])
		let alias = try #require(owner.root["alias"])
		for _ in 0..<3 {
			#expect(empty.type.count == 16)
			#expect(alias.type.keys == empty.type.keys)
			#expect(empty.defaultValue == nil && alias.defaultValue == nil)
			#expect(value.defaultValue == .literal(.string("first")))
			for level in 0...6 {
				#expect(empty.type.keys.contains(try Lemma.ID(parsing: "probe.left\(level)")))
				#expect(empty.type.keys.contains(try Lemma.ID(parsing: "probe.right\(level)")))
			}
		}
	}

	@Test func default_search_is_per_query_and_old_generations_remain_independent() throws {
		let owner = try Lexicon(document: document(depth: 4), selectedRoot: "probe")
		let old = owner.root
		#expect(old["empty"]?.defaultValue == nil)
		#expect(old["value"]?.defaultValue == .literal(.string("first")))
		try owner.replaceDocument(with: document(depth: 4, baseDefault: "changed"), selectedRoot: "probe")
		for _ in 0..<3 {
			#expect(owner.root["empty"]?.defaultValue == .literal(.string("changed")))
			#expect(owner.root["value"]?.defaultValue == .literal(.string("changed")))
			#expect(old["empty"]?.defaultValue == nil)
			#expect(old["value"]?.defaultValue == .literal(.string("first")))
		}
	}
}
