//
// github.com/screensailor 2026
//

import Foundation

final class DocumentMetadataTests: Hopes {

	func test_taskpaper_document_metadata_round_trip() throws {

		let document = try TaskPaper("""
			# document comment
			> document note
			@ local.lexicon
			@ https://example.com/remote.lexicon
			root:
			# root comment
			> root note
			? {"count":2,"enabled":true}
				connected:
				@ local.lexicon
				@ https://example.com/remote.lexicon
				alias:
				= root.value
				value:
				? "fallback"
				+ root.type
			""").decodeDocument()

		hope(document.comments) == ["document comment"]
		hope(document.notes) == ["document note"]
		hope(document.imports.map(\.reference)) == [
			"local.lexicon",
			"https://example.com/remote.lexicon",
		]
		hope(document.imports.map(\.location)) == [.local, .remote]
		hope(document.roots.keys.sorted()) == ["root"]

		let root = try document.roots["root"].try()
		hope(root.comments) == ["root comment"]
		hope(root.notes) == ["root note"]
		hope(root.defaultValue) == .literal(.object([
			"count": .number(2),
			"enabled": .bool(true),
		]))

		let connected = try root.children["connected"].try()
		hope(connected.connections.map(\.reference)) == [
			"local.lexicon",
			"https://example.com/remote.lexicon",
		]

		let alias = try root.children["alias"].try()
		hope(alias.protonym) == "root.value"

		let value = try root.children["value"].try()
		hope(value.defaultValue) == .literal(.string("fallback"))
		hope(value.type) == ["root.type"]

		let encoded = TaskPaper.encode(document)
		let roundTrip = try TaskPaper(encoded).decodeDocument()

		hope(TaskPaper.encode(roundTrip)) == encoded
		hope(try roundTrip.roots["root"].try().comments) == ["root comment"]
		hope(try roundTrip.roots["root"].try().children["value"].try().defaultValue) == .literal(.string("fallback"))
	}

	func test_taskpaper_document_preserves_multiple_roots() throws {

		let document = try TaskPaper("""
			zeta:
				last:
			alpha:
				first:
			""").decodeDocument()

		hope(document.roots.keys.sorted()) == ["alpha", "zeta"]
		hope(try document.roots["alpha"].try().children.keys.sorted()) == ["first"]
		hope(try document.roots["zeta"].try().children.keys.sorted()) == ["last"]

		let graph = try TaskPaper("""
			zeta:
			alpha:
			""").decode()
		hope(graph.root.name) == "alpha"

		hope(TaskPaper.encode(document)) == """
			alpha:
				first:
			zeta:
				last:
			"""
	}

	func test_lemma_default_values_resolve_through_types_and_synonyms() async throws {

		let root = try await Lexicon.from(TaskPaper("""
			root:
				kind:
				? "kind default"
					shared:
					? "kind shared"
					unique:
					? "kind unique"
				other:
					shared:
					? "other shared"
				instance:
				+ root.kind
					shared:
					? "own shared"
				own:
				+ root.kind
				? "own default"
				alias:
				= instance
				multi:
				+ root.other
				+ root.kind
			""").decode()).root

		let instance = try await root["instance"].hopefully()
		let inheritedUnique = try await instance["unique"].hopefully()
		let ownShared = try await instance["shared"].hopefully()
		let own = try await root["own"].hopefully()
		let alias = try await root.ownChildren["alias"].try()
		let multiShared = try await root["multi", "shared"].hopefully()

		let instanceDefault = await instance.defaultValue
		let inheritedUniqueDefault = await inheritedUnique.defaultValue
		let ownSharedDefault = await ownShared.defaultValue
		let ownDefault = await own.defaultValue
		let aliasDefault = await alias.defaultValue
		let multiSharedDefault = await multiShared.defaultValue

		hope(instanceDefault) == .literal(.string("kind default"))
		hope(inheritedUniqueDefault) == .literal(.string("kind unique"))
		hope(ownSharedDefault) == .literal(.string("own shared"))
		hope(ownDefault) == .literal(.string("own default"))
		hope(aliasDefault) == .literal(.string("kind default"))
		hope(multiSharedDefault) == .literal(.string("kind shared"))
	}

	func test_json_classes_include_default_values_and_notes() async throws {

		let json = try await Lexicon.from(TaskPaper("""
			root:
			> root note
			? @ root.kind
				kind:
				? "kind default"
			""").decode()).json()

		let root = try json.classes.first { $0.id == "root" }.try()
		let kind = try json.classes.first { $0.id == "root.kind" }.try()

		hope(root.defaultValue) == .reference("root.kind")
		hope(root.notes) == ["root note"]
		hope(kind.defaultValue) == .literal(.string("kind default"))
	}

	func test_document_codable_preserves_node_metadata() throws {

		let document = Lexicon.Document(
			date: Date(timeIntervalSinceReferenceDate: 0),
			roots: [
				"root": .init(
					name: "root",
					children: [
						"value": .init(
							name: "value",
							type: ["root.type"],
							stableID: "stable-value",
							defaultValue: .reference("root.default"),
							connections: [.init("https://example.com/remote.lexicon")],
							notes: ["node note"],
							comments: ["node comment"]
						),
					],
					notes: ["root note"]
				),
			],
			imports: [.init("local.lexicon")],
			notes: ["document note"],
			comments: ["document comment"]
		)

		let data = try JSONEncoder().encode(document)
		let decoded = try JSONDecoder().decode(Lexicon.Document.self, from: data)
		let value = try decoded.roots["root"].try().children["value"].try()

		hope(decoded.imports) == [.init("local.lexicon")]
		hope(decoded.notes) == ["document note"]
		hope(try decoded.roots["root"].try().notes) == ["root note"]
		hope(value.stableID) == "stable-value"
		hope(value.defaultValue) == .reference("root.default")
		hope(value.connections) == [.init("https://example.com/remote.lexicon")]
		hope(value.notes) == ["node note"]
		hope(value.comments) == ["node comment"]
	}
}
