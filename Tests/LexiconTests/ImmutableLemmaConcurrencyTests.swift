import Lexicon
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ImmutableLemmaConcurrencyTests {
    @Test func retained_generations_support_parallel_queries_during_live_edits() async throws {
        let owner = try await Lexicon(document: document("Before"), selectedRoot: "app")
        let original = await owner.root
        let readers = Task { @concurrent in try await readConcurrently(original, expected: "Before") }
        try await owner.replaceDocument(with: document("After"), selectedRoot: "shared")
        let current = await owner.root
        try await readers.value
        try await readConcurrently(current, expected: "After")
        #expect(original.lexiconID == current.lexiconID)
        #expect(original.revision != current.revision)
        try query(original, expected: "Before")
    }

    private func readConcurrently(_ root: Lemma, expected: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    for _ in 0..<32 { try query(root, expected: expected) }
                }
            }
            try await group.waitForAll()
        }
    }

    // Synchronous and nonisolated: captured schema reads need no live-model actor.
    private func query(_ root: Lemma, expected: String) throws {
        let type = try #require(root[id: "shared.template"])
        let item = try #require(root[id: "app.item"])
        let alias = try #require(root[id: "app.alias"])
        #expect(item.is(type) && alias.is(type))
        #expect(item.type == alias.type)
        #expect(item.children["label"] == item["label"])
        var traversal: [Lemma.ID] = []
        item.graphTraversal(.depthFirst) { traversal.append($0.id) }
        #expect(traversal == ["app.item", "app.item.caption"])
        for field in [try #require(item["label"]), try #require(alias["caption"])] {
            #expect(field.source.id == "shared.template.label")
            #expect(field.defaultValue == .literal(.string(expected)))
            #expect(field.revision == root.revision && field.lexiconID == root.lexiconID)
            #expect(Array(field.lineage.map(\.id)).last == "app")
        }
        #expect(root[id: "app.alias.missing"] == nil)
    }

    private func document(_ value: String) throws -> Lexicon.Document {
        try TaskPaper("""
        shared:
        \ttemplate:
        \t\tlabel:
        \t\t? "\(value)"
        app:
        \titem:
        \t+ shared.template
        \t\tcaption:
        \t\t= label
        \talias:
        \t= item
        """).decodeDocument()
    }
}
