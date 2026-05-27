//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct CRDTDocumentMergeTests {

	@Test
	func test_crdt_replay_order_independent() throws {

		let local = Lexicon.Import("local.lexicon")
		let remote = Lexicon.Import("https://example.com/base.lexicon")
		let operations: [Lexicon.CRDT.Operation] = [
			.operation(1, "a", .createNode(path: "root", parentPath: nil, name: "root")),
			.operation(2, "a", .createNode(path: "root.alpha", parentPath: "root", name: "alpha")),
			.operation(3, "b", .createNode(path: "root.beta", parentPath: "root", name: "beta")),
			.operation(4, "a", .addTypeReference(path: "root.alpha", type: "root.kind")),
			.operation(5, "a", .setDefaultValue(path: "root.alpha", value: .literal(.string("value")))),
			.operation(6, "b", .addNote(path: "root.alpha", noteID: "note", text: "note")),
			.operation(7, "b", .addImport(local)),
			.operation(8, "a", .removeImport(local)),
			.operation(9, "a", .addImport(remote)),
			.operation(10, "b", .deleteNode(path: "root.beta")),
			.operation(11, "a", .addComment(path: "root.alpha", commentID: "comment", text: "comment")),
		]

		var left = Lexicon.CRDT.Replica()
		var right = Lexicon.CRDT.Replica()
		for operation in operations.enumerated() {
			if operation.offset.isMultiple(of: 2) {
				left.apply(operation.element)
			} else {
				right.apply(operation.element)
			}
		}

		var leftThenRight = left
		leftThenRight.merge(right)
		var rightThenLeft = right
		rightThenLeft.merge(left)

		let encoded = TaskPaper.encode(leftThenRight.materialized())
		#expect(encoded == TaskPaper.encode(rightThenLeft.materialized()))
		#expect(encoded == """
			@ https://example.com/base.lexicon
			root:
				alpha:
				# comment
				> note
				? "value"
				+ root.kind
			""")
	}

	@Test
	func test_crdt_replica_json_round_trip() throws {

		var replica = Lexicon.CRDT.Replica()
		replica.apply(.operation(1, "a", .createNode(path: "root", parentPath: nil, name: "root")))
		replica.apply(.operation(3, "a", .setDefaultValue(path: "root.value", value: .literal(.object([
			"count": .number(2),
			"enabled": .bool(true),
		])))))
		replica.apply(.operation(2, "a", .createNode(path: "root.value", parentPath: "root", name: "value")))

		#expect(replica.json.operations.map(\.id.counter) == [1, 2, 3])
		let data = try JSONEncoder().encode(replica.json)
		let decoded = try Lexicon.CRDT.Replica(JSONDecoder().decode(Lexicon.CRDT.Replica.JSON.self, from: data))

		#expect(TaskPaper.encode(decoded.materialized()) == """
			root:
				value:
				? {"count":2,"enabled":true}
			""")
	}

	@Test
	func test_document_merge_and_composition_are_deterministic() throws {

		let imported = try TaskPaper("""
			external:
				imported:
				type:
				reference:
				+ external.type
				? @ external.type
			""").decodeDocument()
		let local = try TaskPaper("""
			shared:
				connected:
				@ imported.lexicon
					local:
			""").decodeDocument()

		let composed = try local.composed(resolving: DictionaryLexiconImportResolver([
			"imported.lexicon": imported,
		]))

		#expect(composed.conflicts == [])
		#expect(composed.document.roots.keys.sorted() == ["shared"])
		let connected = try composed.document.roots["shared"].try().children["connected"].try()
		#expect(connected.connections == [])
		#expect(connected.children.keys.sorted() == [
			"imported",
			"local",
			"reference",
			"type",
		])
		#expect(try connected.children["reference"].try().type == Set(["shared.connected.type"]))
		#expect(try connected.children["reference"].try().defaultValue == .reference("shared.connected.type"))

		let left = try TaskPaper("""
			root:
				value:
				? "left"
			""").decodeDocument()
		let right = try TaskPaper("""
			root:
				value:
				? "right"
					child:
			""").decodeDocument()

		let plan = left.merging(right)

		#expect(plan.conflicts == [])
		#expect(try plan.document.roots["root"].try().children["value"].try().defaultValue == .literal(.string("right")))
		#expect(try plan.document.roots["root"].try().children["value"].try().children.keys.sorted() == ["child"])

		let reversed = right.merging(left)
		#expect(reversed.conflicts == [])
		#expect(try reversed.document.roots["root"].try().children["value"].try().defaultValue == .literal(.string("left")))

		let external = try TaskPaper("""
			external:
				child:
			""").decodeDocument()
		let grafted = left.merging(external)
		#expect(grafted.conflicts == [])
		#expect(grafted.document.roots.keys.sorted() == ["root"])
		#expect(try grafted.document.roots["root"].try().children["external"].try().children.keys.sorted() == ["child"])
	}

	@Test
	func test_composition_uses_crdt_overlay_order() throws {

		let imported = try TaskPaper("""
			root:
				value:
				? "imported"
			""").decodeDocument()
		let local = try TaskPaper("""
			@ imported.lexicon
			root:
				value:
				? "local"
					child:
			""").decodeDocument()

		let composed = try local.composed(resolving: DictionaryLexiconImportResolver([
			"imported.lexicon": imported,
		]))

		#expect(composed.conflicts == [])
		#expect(try composed.document.roots["root"].try().children["value"].try().defaultValue == .literal(.string("local")))
		#expect(try composed.document.roots["root"].try().children["value"].try().children.keys.sorted() == ["child"])
	}

	@Test
	func test_example_connected_lexicons_compose_from_file_connections() throws {

		let source = try Bundle.module.url(
			forResource: "Resources/Examples/connected-root.taskpaper",
			withExtension: nil
		).try()
		let document = try TaskPaper(Data(contentsOf: source)).decodeDocument()
		let composed = try document.composed(resolving: FileLexiconImportResolver(
			baseURL: source.deletingLastPathComponent()
		))

		#expect(composed.conflicts == [])
		#expect(composed.document.roots.keys.sorted() == ["organization"])

		let root = try composed.document.roots["organization"].try()
		let products = try root.children["products"].try()
		#expect(products.connections == [])
		#expect(products.children.keys.sorted() == [
			"glossary",
			"local_term",
			"product",
		])
		#expect(try products.children["product"].try().children.keys.sorted() == [
			"roadmap",
		])

		let engineering = try root.children["engineering"].try()
		#expect(engineering.connections == [])
		#expect(engineering.children.keys.sorted() == [
			"local_term",
			"quality",
			"runtime",
		])

		let encoded = TaskPaper.encode(composed.document)
		#expect(!(encoded.contains("@ ./products.lexicon")))
		#expect(!(encoded.contains("@ ./engineering.lexicon")))
	}

	@Test
	func test_file_import_resolver_restricts_local_imports_to_base_url() throws {

		let temporary = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let base = temporary.appendingPathComponent("base", isDirectory: true)
		let outside = temporary.appendingPathComponent("outside.lexicon")
		defer { try? FileManager.default.removeItem(at: temporary) }

		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		try Data("outside:\n".utf8).write(to: outside)
		try Data("inside:\n".utf8).write(to: base.appendingPathComponent("inside.lexicon"))

		let resolver = FileLexiconImportResolver(baseURL: base)

		let resolved = try resolver.resolve(.init(reference: "inside.lexicon", location: .local))
		#expect(try resolved.try().roots.keys.first == "inside")
		#expect(try resolver.resolve(.init(reference: "../outside.lexicon", location: .local)) == nil)
		#expect(try resolver.resolve(.init(reference: outside.path, location: .local)) == nil)
	}

	@Test
	func test_file_import_resolver_rejects_non_http_remote_urls() throws {

		let resolver = FileLexiconImportResolver(
			baseURL: FileManager.default.temporaryDirectory,
			allowRemote: true
		)

		#expect(try resolver.resolve(.init(reference: "file:///tmp/import.lexicon", location: .remote)) == nil)
		#expect(try resolver.resolve(.init(reference: "ftp://example.com/import.lexicon", location: .remote)) == nil)
	}
}

private extension Lexicon.CRDT.Operation {

	static func operation(
		_ counter: UInt64,
		_ actor: String,
		_ kind: Lexicon.CRDT.Kind
	) -> Self {
		.init(kind, id: .init(actor: actor, counter: counter))
	}
}
