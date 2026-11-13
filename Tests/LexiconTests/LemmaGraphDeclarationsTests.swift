import Lexicon
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LemmaGraphDeclarationsTests {
    @Test func declarations_remain_distinct_from_alias_sources_and_inherited_placements() async throws {
        let owner = try await Lexicon(document: document(updated: false), selectedRoot: "app")
        try query(await owner.root, updated: false)
    }

    @Test func parallel_declaration_reads_keep_the_captured_generation_after_replacement() async throws {
        let owner = try await Lexicon(document: document(updated: false), selectedRoot: "app")
        let before = await owner.root
        let readers = Task { @concurrent in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        for _ in 0..<16 { try query(before, updated: false) }
                    }
                }
                try await group.waitForAll()
            }
        }
        try await owner.replaceDocument(with: document(updated: true), selectedRoot: "shared")
        let after = await owner.root
        try await readers.value
        #expect(before.revision != after.revision && before.lexiconID == after.lexiconID)
        try query(before, updated: false)
        try query(after, updated: true)
    }

    private func query(_ root: Lemma, updated: Bool) throws {
        let declarations: [Lemma.ID] = ["app", "app.item", "app.alias", "shared.kind", "shared.kind.title", "shared.cleared"]
        for id in declarations {
            let resolved = try #require(root[id: id])
            #expect(root.graphNode(at: id) == resolved.graphNode)
        }
        let source = try #require(root.graphNode(at: "shared.kind.title"))
        #expect(source == root.document.roots["shared"]?.children["kind"]?.children["title"])
        #expect(source.defaultValue != nil)
        #expect(root.graphNode(at: "shared.cleared")?.defaultValue != nil)
        #expect(root.graphNode(at: "app.alias")?.protonym != nil)
        let inherited = try #require(root[id: "app.item.title"])
        #expect(inherited.source.graphNode == source)
        #expect(root.graphNode(at: inherited.id) == nil)
        #expect(root.graphNode(at: "app.alias.title") == nil)
        #expect(root.graphNode(at: "absent") == nil)
        #expect((root.graphNode(at: "shared.extra") != nil) == updated)
    }

    private func document(updated: Bool) throws -> Lexicon.Document {
        let text = updated ? "New coffee" : "Coffee"
        let extra = updated ? "\n\textra:" : ""
        return try TaskPaper("""
        shared:
        \tkind:
        \t\ttitle:
        \t\t? "\(text)"
        \tcleared:
        \t? null\(extra)
        app:
        \titem:
        \t+ shared.kind
        \talias:
        \t= item
        """).decodeDocument()
    }
}
