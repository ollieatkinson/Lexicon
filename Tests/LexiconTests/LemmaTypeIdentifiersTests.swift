import Lexicon
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LemmaTypeIdentifiersTests {
    @Test func identifiers_match_handles_through_diamonds_aliases_and_inherited_fields() async throws {
        let owner = try await Lexicon(document: document(extra: false), selectedRoot: "app")
        try query(await owner.root, extra: false)
    }

    @Test func captured_type_identifiers_stay_in_their_generation_during_parallel_reads() async throws {
        let owner = try await Lexicon(document: document(extra: false), selectedRoot: "app")
        let before = await owner.root
        let readers = Task { @concurrent in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        for _ in 0..<16 { try query(before, extra: false) }
                    }
                }
                try await group.waitForAll()
            }
        }
        try await owner.replaceDocument(with: document(extra: true), selectedRoot: "shared")
        let after = await owner.root
        try await readers.value
        #expect(before.revision != after.revision && before.lexiconID == after.lexiconID)
        try query(before, extra: false)
        try query(after, extra: true)
    }

    private func query(_ root: Lemma, extra: Bool) throws {
        let item = try #require(root[id: "app.item"])
        let alias = try #require(root[id: "app.alias"])
        let field = try #require(item["title"])
        #expect(item.typeIDs == alias.typeIDs)
        #expect(item.typeIDs.contains("shared.extra") == extra)
        for node in [item, alias, field] {
            #expect(node.typeIDs == Array(node.type.keys))
            #expect(Set(node.typeIDs).count == node.typeIDs.count)
            for id in node.typeIDs {
                let handle = try #require(node[id: id])
                #expect(handle.lexiconID == root.lexiconID && handle.revision == root.revision)
            }
        }
        #expect(field.typeIDs.contains("shared.kind.title"))
    }

    private func document(extra: Bool) throws -> Lexicon.Document {
        let extraType = extra ? "\n\t+ shared.extra" : ""
        return try TaskPaper("""
        shared:
        \tkind:
        \t\ttitle:
        \t\t? "Coffee"
        \tleft:
        \t+ shared.kind
        \tright:
        \t+ shared.kind
        \textra:
        app:
        \titem:
        \t+ shared.left
        \t+ shared.right\(extraType)
        \talias:
        \t= item
        """).decodeDocument()
    }
}
