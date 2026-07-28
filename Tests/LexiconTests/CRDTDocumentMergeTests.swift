//
// github.com/screensailor 2026
//

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Lexicon

@Suite

struct CRDTDocumentMergeTests {

	@Test
	func test_crdt_replay_order_independent() throws {

		let local = Lexicon.Import("local.lexicon")
		let remote = Lexicon.Import("https://example.com/base.lexicon")
		let root = Lexicon.CRDT.Operation.operation(
			1,
			"a",
			.createNode(path: "root", parentPath: nil, name: "root")
		)
		let localImport = Lexicon.CRDT.Operation.operation(
			8,
			"a",
			.insertImport(after: nil, value: local)
		)
		var left = Lexicon.CRDT.Replica()
		var right = Lexicon.CRDT.Replica()
		try left.apply(root)
		try left.apply(.operation(2, "a", .createNode(path: "root.kind", parentPath: "root", name: "kind")))
		try left.apply(.operation(3, "a", .createNode(path: "root.alpha", parentPath: "root", name: "alpha")))
		try left.apply(.operation(4, "a", .addTypeReference(path: "root.alpha", type: "root.kind")))
		try left.apply(.operation(5, "a", .setDefaultValue(path: "root.alpha", value: .literal(.string("value")))))
		try left.apply(.operation(6, "a", .insertNote(path: "root.alpha", after: nil, text: "note")))
		try left.apply(.operation(7, "a", .insertComment(path: "root.alpha", after: nil, text: "comment")))
		try left.apply(localImport)
		try left.apply(.operation(9, "a", .removeImport(element: localImport.id)))

		try right.apply(root)
		try right.apply(.operation(10, "b", .createNode(path: "root.beta", parentPath: "root", name: "beta")))
		try right.apply(.operation(11, "b", .deleteNode(path: "root.beta")))
		try right.apply(.operation(12, "b", .insertImport(after: nil, value: remote)))

		var leftThenRight = left
		try leftThenRight.merge(right)
		var rightThenLeft = right
		try rightThenLeft.merge(left)

		let encoded = TaskPaper.encode(try leftThenRight.materialized())
		let reversed = TaskPaper.encode(try rightThenLeft.materialized())
		#expect(encoded == reversed)
		#expect(encoded == """
			@ https://example.com/base.lexicon
			root:
				alpha:
				# comment
				> note
				? "value"
				+ root.kind
				kind:
			""")
	}

	@Test
	func test_crdt_parent_deletion_hides_descendants_and_converges() throws {
		let root = Lexicon.CRDT.Operation.operation(
			1,
			"base",
			.createNode(path: "root", parentPath: nil, name: "root")
		)
		let parent = Lexicon.CRDT.Operation.operation(
			2,
			"base",
			.createNode(path: "root.parent", parentPath: "root", name: "parent")
		)
		let deletion = Lexicon.CRDT.Operation.operation(
			3,
			"left",
			.deleteNode(path: "root.parent")
		)
		let child = Lexicon.CRDT.Operation.operation(
			3,
			"right",
			.createNode(
				path: "root.parent.child",
				parentPath: "root.parent",
				name: "child"
			)
		)

		var left = try Lexicon.CRDT.Replica(operations: [root, parent])
		try left.apply(deletion)
		let deletedDocument = try left.materialized()
		#expect(deletedDocument.roots.keys.sorted() == ["root"])
		#expect(deletedDocument.roots["root"]?.children.isEmpty == true)

		var right = try Lexicon.CRDT.Replica(operations: [root, parent])
		try right.apply(child)

		var leftThenRight = left
		try leftThenRight.merge(right)
		var rightThenLeft = right
		try rightThenLeft.merge(left)

		#expect(try leftThenRight.materialized() == rightThenLeft.materialized())
		let mergedDocument = try leftThenRight.materialized()
		#expect(mergedDocument.roots.keys.sorted() == ["root"])
		#expect(mergedDocument.roots["root"]?.children.isEmpty == true)
		#expect(
			try leftThenRight.materialization().materializedPath(
				forNodeAddress: "root.parent.child"
			) == nil
		)

		var recreated = leftThenRight
		try recreated.apply(.operation(
			4,
			"repair",
			.createNode(path: "root.parent", parentPath: "root", name: "parent")
		))
		#expect(
			try recreated.materialized()
				.roots["root"]?.children["parent"]?.children.isEmpty == true
		)
		try recreated.apply(.operation(
			5,
			"repair",
			.createNode(
				path: "root.parent.child",
				parentPath: "root.parent",
				name: "child"
			)
		))
		#expect(
			try recreated.materialized()
				.roots["root"]?.children["parent"]?.children.keys.sorted() == ["child"]
		)
	}

	@Test
	func test_crdt_replica_json_round_trip() throws {

		var replica = Lexicon.CRDT.Replica()
		try replica.apply(.operation(1, "a", .createNode(path: "root", parentPath: nil, name: "root")))
		try replica.apply(.operation(2, "a", .createNode(path: "root.value", parentPath: "root", name: "value")))
		try replica.apply(.operation(3, "a", .setDefaultValue(path: "root.value", value: .literal(.object([
			"count": .number(2),
			"enabled": .bool(true),
		])))))

		#expect(replica.json.operations.map(\.id.timestamp) == [1, 2, 3])
		let data = try JSONEncoder().encode(replica.json)
		let decoded = try Lexicon.CRDT.Replica(JSONDecoder().decode(Lexicon.CRDT.Replica.JSON.self, from: data))
		let materialized = try decoded.materialized()

		#expect(TaskPaper.encode(materialized) == """
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
		let mergedRoots = left.merging(external)
		#expect(mergedRoots.conflicts == [])
		#expect(mergedRoots.document.roots.keys.sorted() == ["external", "root"])
		#expect(
			try mergedRoots.document.roots["external"].try().children.keys.sorted() ==
				["child"]
		)
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
				baseURL: source.deletingLastPathComponent(),
				rootURL: source
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

	@Test
	func test_remote_import_origins_include_scheme_host_and_effective_port() throws {
		let origin = try #require(URL(string: "https://EXAMPLE.com/root.lexicon"))
		let sameOrigin = try #require(URL(string: "https://example.com:443/nested.lexicon"))
		let otherScheme = try #require(URL(string: "http://example.com/nested.lexicon"))
		let otherHost = try #require(URL(string: "https://other.example/nested.lexicon"))
		let otherPort = try #require(URL(string: "https://example.com:8443/nested.lexicon"))

		#expect(sameOrigin.hasSameOrigin(as: origin))
		#expect(!otherScheme.hasSameOrigin(as: origin))
		#expect(!otherHost.hasSameOrigin(as: origin))
		#expect(!otherPort.hasSameOrigin(as: origin))
	}

	@Test
	func test_connection_graft_failure_preserves_nested_diagnostics_in_order() throws {
		let connected = Lexicon.Document(
			roots: [
				"first": .init(),
				"second": .init(),
			],
			imports: [
				.init("missing-first"),
				.init("missing-second"),
			]
		)
		let local = Lexicon.Document(roots: [
			"root": .init(children: [
				"anchor": .init(connections: [.init("connected")]),
			]),
		])

		let result = try local.composed(
			resolving: DictionaryLexiconImportResolver(["connected": connected])
		)

		#expect(result.conflicts.map(\.kind) == [
			.importResolution,
			.importResolution,
			.invalidGraft,
		])
		#expect(result.conflicts.map(\.path) == [
			"missing-first",
			"missing-second",
			"root.anchor",
		])
		#expect(result.conflicts[0].existing == "unresolved")
		#expect(result.conflicts[1].existing == "unresolved")
		#expect(result.conflicts[2].existing == "connected")
		#expect(
			result.document.roots["root"]?
				.children["anchor"]?
				.connections == [.init("connected")]
		)
	}

	@Test
	func test_remote_import_loader_enforces_declared_and_streamed_size_limits() throws {
		#expect(FileLexiconImportResolver.maximumRemoteResponseBytes == 1_048_576)
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [RemoteImportURLProtocol.self]
		let boundaryURL = try #require(
			URL(string: "https://remote-import.test/boundary")
		)
		let boundary = try RemoteImportLoader.load(
			boundaryURL,
			allowedRedirectOrigin: nil,
			maximumResponseBytes: 8,
			configuration: configuration
		)
		#expect(boundary.data == Data("12345678".utf8))

		for path in ["declared-oversize", "streamed-oversize"] {
			let url = try #require(URL(string: "https://remote-import.test/\(path)"))
			do {
				_ = try RemoteImportLoader.load(
					url,
					allowedRedirectOrigin: nil,
					maximumResponseBytes: 8,
					configuration: configuration
				)
				Issue.record("Expected \(path) response to exceed the limit.")
			} catch let error as LexiconError {
				#expect(
					error.description ==
						"Remote import exceeds the maximum response size of 8 bytes."
				)
			} catch {
				Issue.record("Unexpected \(path) error: \(error)")
			}
		}
	}

	@Test
	func test_remote_import_redirect_policy_is_same_origin() throws {
		let origin = try #require(URL(string: "https://remote-import.test/root"))
		let sameOrigin = try #require(
			URL(string: "https://REMOTE-IMPORT.test:443/redirected")
		)
		let crossOrigin = try #require(
			URL(string: "https://elsewhere.test/redirected")
		)

		#expect(RemoteImportLoader.redirectIsAllowed(
			to: sameOrigin,
			allowedOrigin: origin
		))
		#expect(!RemoteImportLoader.redirectIsAllowed(
			to: crossOrigin,
			allowedOrigin: origin
		))
		#expect(RemoteImportLoader.redirectIsAllowed(
			to: crossOrigin,
			allowedOrigin: nil
		))
	}
}

private final class RemoteImportURLProtocol: URLProtocol {
	override class func canInit(with request: URLRequest) -> Bool {
		request.url?.host == "remote-import.test"
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		guard let url = request.url else {
			client?.urlProtocol(
				self,
				didFailWithError: LexiconError("Missing stub request URL")
			)
			return
		}

		let headers = url.lastPathComponent == "declared-oversize"
			? ["Content-Length": "9"]
			: [:]
		guard let response = HTTPURLResponse(
			url: url,
			statusCode: 200,
			httpVersion: "HTTP/1.1",
			headerFields: headers
		) else {
			client?.urlProtocol(
				self,
				didFailWithError: LexiconError("Could not create stub response")
			)
			return
		}
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

		if url.lastPathComponent == "streamed-oversize" {
			client?.urlProtocol(self, didLoad: Data("12345".utf8))
			client?.urlProtocol(self, didLoad: Data("6789".utf8))
		} else if url.lastPathComponent == "boundary" {
			client?.urlProtocol(self, didLoad: Data("12345678".utf8))
		}
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

private extension Lexicon.CRDT.Operation {

	static func operation(
		_ timestamp: UInt64,
		_ actor: String,
		_ kind: Lexicon.CRDT.Kind
	) -> Self {
		.init(kind, id: .init(timestamp: timestamp, actor: actor))
	}
}
