import Foundation
import Testing
@testable import Lexicon

@Suite
struct TypedIdentityTests {

	@Test(arguments: [
		("alpha", true),
		("_alpha", true),
		("_123", true),
		("a١", true),
		("e\u{301}", true),
		("a_", true),
		("", false),
		("_", false),
		("1alpha", false),
		("a__b", false),
		("a-b", false),
		("aⅣ", false),
		("a½", false),
	])
	func nameGrammar(candidate: String, valid: Bool) {
		#expect(Lemma.Name.isValid(candidate) == valid)
		#expect(((try? Lemma.Name(validating: candidate)) != nil) == valid)
	}

	@Test
	func incrementalUnderscorePrefix() {
		#expect(Lemma.Name.isValidPrefix("_"))
		#expect(Lemma.isValid(character: "_", appendingTo: ""))
		#expect(!Lemma.Name.isValid("_"))
		#expect(!Lemma.isValid(character: "_", appendingTo: "_"))
	}

	@Test
	func typedAbsoluteAndRelativePaths() throws {
		let id = try Lemma.ID(parsing: "root.child.value")
		let relative = try Lemma.RelativeID(parsing: "child.value")

		#expect(id.root == "root")
		#expect(id.name == "value")
		#expect(id.parent == "root.child")
		#expect(Lemma.ID(root: "root").appending(relative) == id)
		#expect(try id.relative(to: "root") == relative)
		#expect(id.isDescendant(of: "root"))
		#expect(!id.isDescendant(of: "other"))
	}

	@Test
	func importLocationRecognizesOnlyAbsoluteHTTPURLsAsRemote() {
		#expect(Lexicon.Import("https://example.com/shared.lexicon").location == .remote)
		#expect(Lexicon.Import("HTTP://example.com/shared.lexicon").location == .remote)
		#expect(Lexicon.Import("http-not-a-url.lexicon").location == .local)
		#expect(Lexicon.Import("ftp://example.com/shared.lexicon").location == .local)
		#expect(Lexicon.Import("/shared.lexicon").location == .local)
	}
}

@Suite
struct StrictTaskPaperTests {

	@Test
	func parserReportsIndentationDuplicatesUnknownLinesAndMisplacedMetadata() {
		let result = TaskPaper("""
		 @ invalid-leading-space
		root:
			child:
					jump:
			+ root.child
			+ root.child
			= child
			= child
			? 1
			? 2
		unknown
		root:
		""").parse()

		let codes = result.diagnostics.map(\.code)
		#expect(codes.contains(.leadingSpaces))
		#expect(codes.contains(.indentationJump))
		#expect(codes.contains(.duplicateType))
		#expect(codes.contains(.duplicateProtonym))
		#expect(codes.contains(.duplicateDefault))
		#expect(codes.contains(.unknownLine))
		#expect(codes.contains(.duplicateRoot))
	}

	@Test
	func duplicateDocumentAndNodeImportsAreErrors() {
		let result = TaskPaper("""
		@ shared
		@ shared
		root:
		@ nested
		@ nested
		""").parse()

		#expect(result.diagnostics.map(\.code).contains(.duplicateImport))
		#expect(result.diagnostics.map(\.code).contains(.duplicateConnection))
	}

	@Test
	func documentMetadataBeforeTheFirstRootMustNotBeIndented() {
		let source = "\t# indented comment\n\t> indented note\n\t@ indented.lexicon\nroot:\n"
		let result = TaskPaper(source).parse()

		#expect(
			result.diagnostics.filter { $0.code == .misplacedMetadata }.count == 3
		)
		#expect(result.document.comments.isEmpty)
		#expect(result.document.notes.isEmpty)
		#expect(result.document.imports.isEmpty)
		#expect(result.document.roots["root"] != nil)
		#expect(throws: TaskPaper.ParseError.self) {
			try TaskPaper(source).decodeDocument()
		}
	}

	@Test
	func metadataRequiresTheExactActiveIndentationDepth() throws {
		let result = TaskPaper("""
		root:
			parent:
				child:
			> shallower note
					> deeper note
		""").parse()

		#expect(
			result.diagnostics.filter { $0.code == .misplacedMetadata }.count == 2
		)

		let document = try TaskPaper("""
		root:
			parent:
				child:
				> child note
		""").decodeDocument()
		#expect(document.roots["root"]?.children["parent"]?.children["child"]?.notes == ["child note"])
	}

	@Test
	func sourceMapUsesExactZeroBasedUTF16ReferenceRanges() {
		let source = """
		røot:
			item:
			+ røot.kind
			? @ røot.default
		"""
		let map = TaskPaper(source).sourceMap()

		#expect(map.lines.first?.line == 0)
		for line in map.references {
			guard let range = line.referenceRange else {
				Issue.record("A reference source-map entry must have a UTF-16 range")
				continue
			}
			#expect(source.substring(utf16: range) == line.reference)
		}
	}

	@Test
	func malformedDefaultReferenceSpacingIsRejectedInsteadOfMisranged() {
		for source in [
			"root:\n? @root.kind",
			"root:\n? @  root.kind",
		] {
			let result = TaskPaper(source).parse()
			#expect(result.diagnostics.map(\.code).contains(.invalidReference))
			#expect(result.sourceMap.references.isEmpty)
		}
	}

	@Test
	func multipleRootsRequireExplicitGraphSelection() throws {
		let parser = TaskPaper("""
		alpha:
		beta:
		""")

		let document = try parser.decodeDocument()
		#expect(document.roots.keys == ["alpha", "beta"])
		#expect(try parser.decodeGraph(root: "beta").rootName == "beta")
		#expect(didThrow { _ = try parser.decodeGraph(root: "missing") })
	}

	@Test
	func importAndConnectionOrderSurvivesTextAndJSONRoundTrips() throws {
		let document = try TaskPaper("""
		@ zeta
		@ alpha
		root:
		@ nested-zeta
		@ nested-alpha
		""").decodeDocument()

		let encoded = TaskPaper.encode(document)
		#expect(encoded.firstRange(of: "@ zeta")!.lowerBound < encoded.firstRange(of: "@ alpha")!.lowerBound)
		#expect(
			encoded.firstRange(of: "@ nested-zeta")!.lowerBound <
			encoded.firstRange(of: "@ nested-alpha")!.lowerBound
		)
		#expect(document.json.imports?.map(\.reference) == ["zeta", "alpha"])
		let rootJSON = try #require(document.json.roots?.first)
		#expect(rootJSON.connections?.map(\.reference) == ["nested-zeta", "nested-alpha"])
	}
}

@Suite
struct CoreValidationTests {

	@Test(arguments: [
		("""
		root:
			a:
			+ root.a
		""", Lexicon.Diagnostic.Code.typeCycle),
		("""
		root:
			a:
			+ root.b
			b:
			+ root.a
		""", .typeCycle),
		("""
		root:
			a:
			= b
			b:
			= a
		""", .protonymCycle),
		("""
		root:
			a:
			+ root.b
			b:
			= a
		""", .mixedResolutionCycle),
		("""
		alpha:
			a:
			+ beta.b
		beta:
			b:
			+ alpha.a
		""", .typeCycle),
	])
	func detectsCanonicalCycles(source: String, code: Lexicon.Diagnostic.Code) throws {
		let document = try TaskPaper(source).decodeDocument()
		let diagnostic = try #require(document.validate().first { $0.code == code })

		#expect(diagnostic.cycle.first == diagnostic.cycle.last)
		#expect(diagnostic.cycle.first == diagnostic.cycle.dropLast().min())
	}

	@Test
	func acceptsAValidDependencyDiamond() throws {
		let document = try TaskPaper("""
		root:
			base:
			left:
			+ root.base
			right:
			+ root.base
			value:
			+ root.left
			+ root.right
		""").decodeDocument()

		#expect(document.validate().isEmpty)
	}

	@Test
	func reportsUnresolvedAndInvalidSynonymStructure() throws {
		let document = try TaskPaper("""
		root:
			alias:
			= missing
			+ root.missing
				child:
			value:
			? @ root.missing
		""").decodeDocument()
		let codes = Set(document.validate().map(\.code))

		#expect(codes.contains(.unresolvedProtonym))
		#expect(codes.contains(.synonymHasChildren))
		#expect(codes.contains(.synonymHasTypes))
		#expect(codes.contains(.unresolvedType))
		#expect(codes.contains(.unresolvedDefault))
	}

	@Test
	func cycleDiagnosticIsStable() throws {
		let document = try TaskPaper("""
		root:
			z:
			+ root.a
			a:
			+ root.m
			m:
			+ root.z
		""").decodeDocument()

		let first = document.validate()
		let second = document.validate()
		#expect(first == second)
		#expect(first.first?.cycle == ["root.a", "root.m", "root.z", "root.a"])
	}

	@Test
	func reportsEveryCycleKindPresentInsideOneStrongComponent() throws {
		let document = try TaskPaper("""
		root:
			a:
			+ root.b
			b:
			+ root.a
			+ root.c
			c:
			= b
		""").decodeDocument()
		let diagnostics = document.validate()
		let codes = Set(diagnostics.map(\.code))

		#expect(codes.contains(.typeCycle))
		#expect(codes.contains(.mixedResolutionCycle))
		#expect(
			diagnostics
				.filter { [.typeCycle, .mixedResolutionCycle].contains($0.code) }
				.allSatisfy { $0.cycle.first == $0.cycle.last }
		)
	}
}

@Suite
struct CompositionAndCRDTTests {

	@Test
	func laterImportsWinAndLocalSourceWinsLast() throws {
		let first = valueDocument("first")
		let second = valueDocument("second")
		let resolver = DictionaryLexiconImportResolver([
			"first": first,
			"second": second,
		])
		let importedOnly = Lexicon.Document(
			roots: ["root": .init()],
			imports: [.init("first"), .init("second")]
		)

		let imported = try importedOnly.composed(resolving: resolver)
		#expect(imported.conflicts.isEmpty)
		#expect(imported.document.value(at: "root.value") == "second")

		var local = importedOnly
		local.roots["root"]?.children["value"] = .init(
			defaultValue: .literal(.string("local"))
		)
		let composed = try local.composed(resolving: resolver)
		#expect(composed.document.value(at: "root.value") == "local")
	}

	@Test
	func compositionReportsARootImportCycleWithoutDuplicatingTheRoot() throws {
		let first = Lexicon.Document(
			roots: ["first": .init()],
			imports: [.init("second")],
			notes: ["first"]
		)
		let second = Lexicon.Document(
			roots: ["second": .init()],
			imports: [.init("first")],
			notes: ["second"]
		)
		let resolver = DictionaryLexiconImportResolver([
			"first": first,
			"second": second,
		], rootIdentity: "first")

		let result = try first.composed(resolving: resolver)

		#expect(result.document.notes == ["second", "first"])
		#expect(result.document.roots.keys == ["first", "second"])
		#expect(result.conflicts.count == 1)
		#expect(result.conflicts.first?.kind == .importResolution)
		#expect(result.conflicts.first?.existing == "import cycle")
	}

	@Test
	func CRDTIdenticalReplayIsIdempotentAndPayloadCollisionThrows() throws {
		let id = Lexicon.CRDT.OperationID(timestamp: 1, actor: "a")
		let root = Lexicon.CRDT.Operation(
			.createNode(path: "root", parentPath: nil, name: "root"),
			id: id
		)
		var replica = Lexicon.CRDT.Replica()
		try replica.apply(root)
		try replica.apply(root)
		#expect(replica.operations.count == 1)

		let collision = Lexicon.CRDT.Operation(
			.createNode(path: "other", parentPath: nil, name: "other"),
			id: id
		)
		let before = replica.operations
		#expect(didThrow { try replica.apply(collision) })
		#expect(replica.operations == before)
	}

	@Test
	func CRDTMergeAndJSONDecodeRejectCollisionsAtomically() throws {
		let id = Lexicon.CRDT.OperationID(timestamp: 1, actor: "a")
		let leftOperation = Lexicon.CRDT.Operation(
			.createNode(path: "left", parentPath: nil, name: "left"),
			id: id
		)
		let rightOperation = Lexicon.CRDT.Operation(
			.createNode(path: "right", parentPath: nil, name: "right"),
			id: id
		)
		var left = try Lexicon.CRDT.Replica(operations: [leftOperation])
		let right = try Lexicon.CRDT.Replica(operations: [rightOperation])
		let before = left.operations

		#expect(didThrow { try left.merge(right) })
		#expect(left.operations == before)

		var json = left.json
		json.operations.append(.init(rightOperation))
		#expect(didThrow { _ = try Lexicon.CRDT.Replica(json) })
	}

	@Test
	func CRDTUsesUnspecifiedDateAndPreservesDuplicateDeclaredOrder() throws {
		let create = Lexicon.CRDT.Operation(
			.createNode(path: "root", parentPath: nil, name: "root"),
			id: .init(timestamp: 1, actor: "a")
		)
		let undated = try Lexicon.CRDT.Replica(operations: [create])
		#expect(try undated.materialized().date == Lexicon.Document.unspecifiedDate)

		let document = Lexicon.Document(
			roots: ["root": .init(
				connections: [.init("z"), .init("a"), .init("z")],
				notes: ["same", "middle", "same"],
				comments: ["c2", "c1", "c2"]
			)],
			imports: [.init("z"), .init("a"), .init("z")],
			notes: ["same", "middle", "same"],
			comments: ["c2", "c1", "c2"]
		)
		let roundTrip = try Lexicon.CRDT.Replica(document).materialized()

		#expect(roundTrip.imports.map(\.reference) == ["z", "a", "z"])
		#expect(roundTrip.notes == ["same", "middle", "same"])
		#expect(roundTrip.comments == ["c2", "c1", "c2"])
		#expect(roundTrip.roots["root"]?.connections.map(\.reference) == ["z", "a", "z"])
		#expect(roundTrip.roots["root"]?.notes == ["same", "middle", "same"])
		#expect(roundTrip.roots["root"]?.comments == ["c2", "c1", "c2"])
	}

	@Test
	func CRDTRecreationStartsANewNodeMetadataEpoch() throws {
		let operations: [Lexicon.CRDT.Operation] = [
			.init(
				.createNode(path: "root", parentPath: nil, name: "root"),
				id: .init(timestamp: 1, actor: "a")
			),
			.init(
				.createNode(path: "root.kind", parentPath: "root", name: "kind"),
				id: .init(timestamp: 2, actor: "a")
			),
			.init(
				.createNode(path: "root.item", parentPath: "root", name: "item"),
				id: .init(timestamp: 3, actor: "a")
			),
			.init(
				.addTypeReference(path: "root.item", type: "root.kind"),
				id: .init(timestamp: 4, actor: "a")
			),
			.init(
				.setDefaultValue(path: "root.item", value: .literal(.string("old"))),
				id: .init(timestamp: 5, actor: "a")
			),
			.init(
				.insertNote(path: "root.item", after: nil, text: "old"),
				id: .init(timestamp: 6, actor: "a")
			),
			.init(
				.deleteNode(path: "root.item"),
				id: .init(timestamp: 7, actor: "a")
			),
			.init(
				.createNode(path: "root.item", parentPath: "root", name: "item"),
				id: .init(timestamp: 8, actor: "a")
			),
			.init(
				.setDefaultValue(path: "root.item", value: .literal(.string("new"))),
				id: .init(timestamp: 9, actor: "a")
			),
			.init(
				.insertNote(path: "root.item", after: nil, text: "new"),
				id: .init(timestamp: 10, actor: "a")
			),
		]

		let document = try Lexicon.CRDT.Replica(operations: operations).materialized()
		let item = try #require(document.roots["root"]?.children["item"])

		#expect(item.type.isEmpty)
		#expect(item.defaultValue == .literal(.string("new")))
		#expect(item.notes == ["new"])
	}

	@Test
	func CRDTRenamesExposeStableNodeAddressesAndRewriteReferences() throws {
		let operations: [Lexicon.CRDT.Operation] = [
			.init(
				.createNode(path: "root", parentPath: nil, name: "root"),
				id: .init(timestamp: 1, actor: "a")
			),
			.init(
				.createNode(path: "root.kind", parentPath: "root", name: "kind"),
				id: .init(timestamp: 2, actor: "a")
			),
			.init(
				.createNode(path: "root.item", parentPath: "root", name: "item"),
				id: .init(timestamp: 3, actor: "a")
			),
			.init(
				.addTypeReference(path: "root.item", type: "root.kind"),
				id: .init(timestamp: 4, actor: "a")
			),
			.init(
				.renameNode(path: "root.kind", name: "category"),
				id: .init(timestamp: 5, actor: "a")
			),
			.init(
				.renameNode(path: "root.item", name: "entry"),
				id: .init(timestamp: 6, actor: "a")
			),
			.init(
				.setDefaultValue(
					path: "root.item",
					value: .literal(.string("after rename"))
				),
				id: .init(timestamp: 7, actor: "a")
			),
		]

		let materialization = try Lexicon.CRDT.Replica(
			operations: operations
		).materialization()
		let entry = try #require(
			materialization.document.roots["root"]?.children["entry"]
		)

		#expect(entry.type == ["root.category"])
		#expect(entry.defaultValue == .literal(.string("after rename")))
		#expect(
			materialization.materializedPath(forNodeAddress: "root.kind") ==
				"root.category"
		)
		#expect(
			materialization.materializedPath(forNodeAddress: "root.item") ==
				"root.entry"
		)
		#expect(
			materialization.nodeAddress(forMaterializedPath: "root.entry") ==
				"root.item"
		)
	}

	@Test
	func CRDTMergeReportsTheLowestCollidingOperationIDDeterministically() throws {
		let firstID = Lexicon.CRDT.OperationID(timestamp: 1, actor: "a")
		let secondID = Lexicon.CRDT.OperationID(timestamp: 2, actor: "a")
		let left = try Lexicon.CRDT.Replica(operations: [
			Lexicon.CRDT.Operation(
				.createNode(path: "left_first", parentPath: nil, name: "left_first"),
				id: firstID
			),
			Lexicon.CRDT.Operation(
				.createNode(path: "left_second", parentPath: nil, name: "left_second"),
				id: secondID
			),
		])
		let right = try Lexicon.CRDT.Replica(operations: [
			Lexicon.CRDT.Operation(
				.createNode(path: "right_first", parentPath: nil, name: "right_first"),
				id: firstID
			),
			Lexicon.CRDT.Operation(
				.createNode(path: "right_second", parentPath: nil, name: "right_second"),
				id: secondID
			),
		])
		var merged = left
		var caught: Lexicon.CRDT.ReplicaError?

		do {
			try merged.merge(right)
		} catch let error as Lexicon.CRDT.ReplicaError {
			caught = error
		}

		#expect(caught == .operationIDCollision(firstID))
		#expect(merged.operations == left.operations)
	}
}

@Suite
struct SearchEmbeddingValidationTests {

	@Test(arguments: [Lexicon.Search.Scope.live, .full])
	func multiRootExpandedSearchRequiresAnExplicitRoot(
		scope: Lexicon.Search.Scope
	) async throws {
		let document = try TaskPaper("""
		alpha:
			value:
		beta:
			value:
		""").decodeDocument()
		let implicit = Lexicon.Search.Index(
			document: document,
			options: .init(scope: scope)
		)

		#expect(await didThrow {
			_ = try await implicit.search("value", in: document)
		})

		let explicit = Lexicon.Search.Index(
			document: document,
			options: .init(root: "beta", scope: scope)
		)
		_ = try await explicit.search("value", in: document)
	}

	@Test(arguments: InvalidEmbeddingProvider.Failure.allCases)
	private func rejectsMalformedProviderVectors(
		failure: InvalidEmbeddingProvider.Failure
	) async throws {
		let document = try TaskPaper("""
		root:
			value:
		""").decodeDocument()
		let index = Lexicon.Search.Index(document: document)

		#expect(await didThrow {
			_ = try await index.embeddingCache(
				using: InvalidEmbeddingProvider(failure: failure)
			)
		})
	}
}

@Suite
struct GeneratedGraphJSONHardeningTests {

	@Test
	@LexiconActor
	func mixinIdentifiersEncodeUnderscoreBoundaryNamesSafely() throws {
		let document = try TaskPaper("""
		root:
			_kind:
			edge_:
			item:
			+ root._kind
			+ root.edge_
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "root")
		let json = lexicon.json()
		let item = try #require(json.classes.first { $0.id == "root.item" })
		let mixinID = try #require(item.supertype)

		#expect(mixinID.components.count == 1)
		#expect(Lemma.Name.isValid(mixinID.name.rawValue))
		#expect(json.classes.contains { $0.id == mixinID })
	}

	@Test
	@LexiconActor
	func generatedJSONIncludesCompleteDependencyRootsButNotUnrelatedRoots() throws {
		let document = try TaskPaper("""
		shared:
			kind:
			sibling:
		alpha:
			item:
			+ shared.kind
		beta:
			unrelated:
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "alpha")
		let ids = Set(lexicon.json().classes.map(\.id))

		#expect(ids.contains("alpha"))
		#expect(ids.contains("alpha.item"))
		#expect(ids.contains("shared"))
		#expect(ids.contains("shared.kind"))
		#expect(ids.contains("shared.sibling"))
		#expect(!ids.contains("beta"))
		#expect(!ids.contains("beta.unrelated"))
	}

	@Test
	@LexiconActor
	func generatedJSONDoesNotReenterTheSelectedRootThroughADefaultReference() throws {
		let document = try TaskPaper("""
		root:
			kind:
			item:
			? @ root.kind
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "root")

		#expect(Set(lexicon.json().classes.map(\.id)) == [
			"root",
			"root.item",
			"root.kind",
		])
	}
}

#if EDITOR
@Suite
struct TransactionalEditorAndHandleTests {

	@Test
	@LexiconActor
	func rejectsForeignAndStaleHandlesWithoutPublishing() throws {
		let document = try TaskPaper("""
		root:
		""").decodeDocument()
		let first = try Lexicon(document: document, selectedRoot: "root")
		let second = try Lexicon(document: document, selectedRoot: "root")
		let oldRoot = first.root
		let foreignRoot = second.root

		#expect(didThrow { _ = try first.addChild(named: "foreign", to: foreignRoot) })
		let child = try first.addChild(named: "child", to: oldRoot)
		#expect(child.id == "root.child")
		let revision = first.revision
		let currentDocument = first.document

		#expect(didThrow { _ = try first.addChild(named: "stale", to: oldRoot) })
		#expect(first.revision == revision)
		#expect(first.document == currentDocument)
	}

	@Test
	@LexiconActor
	func oldHandlesRemainReadableAndDoNotRetainLexicon() throws {
		var lexicon: Lexicon? = try Lexicon(
			document: TaskPaper("""
			root:
				child:
			""").decodeDocument(),
			selectedRoot: "root"
		)
		weak let weakLexicon = lexicon
		let handle = try #require(lexicon).root
		lexicon = nil

		#expect(weakLexicon == nil)
		#expect(handle.children.keys == ["child"])
		#expect(handle.document.roots.keys == ["root"])
	}

	@Test
	@LexiconActor
	func editsNonselectedRootsAndRewritesCrossRootReferences() throws {
		let document = try TaskPaper("""
		alpha:
			target:
		beta:
			user:
			+ alpha.target
			? @ alpha.target
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "alpha")
		let betaUser = try #require(lexicon["beta.user"])
		_ = try lexicon.addChild(named: "child", to: betaUser)
		let alpha = try #require(lexicon["alpha"])
		let renamed = try lexicon.rename(alpha, to: "gamma")

		#expect(renamed.id == "gamma")
		#expect(lexicon.selectedRoot == "gamma")
		#expect(lexicon.document.roots["beta"]?.children["user"]?.type == ["gamma.target"])
		#expect(
			lexicon.document.roots["beta"]?.children["user"]?.defaultValue ==
			.reference("gamma.target")
		)
		#expect(lexicon["beta.user.child"] != nil)
	}

	@Test
	@LexiconActor
	func referencedDeleteAndCycleEditFailAtomically() throws {
		let document = try TaskPaper("""
		root:
			a:
			b:
			+ root.a
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "root")
		let a = try #require(lexicon["root.a"])
		let b = try #require(lexicon["root.b"])
		let revision = lexicon.revision
		let before = lexicon.document

		#expect(didThrow { try lexicon.delete(a) })
		#expect(didThrow { _ = try lexicon.addType(b, to: a) })
		#expect(lexicon.revision == revision)
		#expect(lexicon.document == before)
	}

	@Test
	@LexiconActor
	func editorAcceptsProtonymChainsAndRejectsAResultingCycle() throws {
		let document = try TaskPaper("""
		root:
			target:
			alias:
			= target
			proposed:
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "root")
		let alias = try #require(lexicon["root.alias"])
		let proposed = try #require(lexicon["root.proposed"])
		let chained = try lexicon.setProtonym(alias, of: proposed)

		#expect(chained.protonym?.id == "root.alias")
		#expect(chained.source.id == "root.target")

		let target = try #require(lexicon["root.target"])
		let revision = lexicon.revision
		let before = lexicon.document
		#expect(didThrow { _ = try lexicon.setProtonym(chained, of: target) })
		#expect(lexicon.revision == revision)
		#expect(lexicon.document == before)
	}

	@Test
	@LexiconActor
	func deletingSelectedRootRejectsAnAmbiguousReplacement() throws {
		let document = try TaskPaper("""
		alpha:
		beta:
		gamma:
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "beta")
		let beta = try #require(lexicon["beta"])
		let revision = lexicon.revision
		let before = lexicon.document

		#expect(didThrow { try lexicon.delete(beta) })
		#expect(lexicon.selectedRoot == "beta")
		#expect(lexicon.revision == revision)
		#expect(lexicon.document == before)
	}

	@Test
	@LexiconActor
	func deletingSelectedRootUsesTheOnlyRemainingRoot() throws {
		let document = try TaskPaper("""
		alpha:
		beta:
		""").decodeDocument()
		let lexicon = try Lexicon(document: document, selectedRoot: "beta")
		let beta = try #require(lexicon["beta"])

		try lexicon.delete(beta)
		#expect(lexicon.selectedRoot == "alpha")
		#expect(lexicon.document.roots.keys == ["alpha"])
	}
}
#endif

private func valueDocument(_ value: String) -> Lexicon.Document {
	.init(roots: [
		"root": .init(children: [
			"value": .init(defaultValue: .literal(.string(value)))
		])
	])
}

private extension Lexicon.Document {

	func value(at id: Lemma.ID) -> String? {
		guard
			let root = roots[id.root],
			let node = try? root.testNode(path: id.components.dropFirst()),
			case .literal(.string(let value)) = node.defaultValue
		else {
			return nil
		}
		return value
	}
}

private extension Lexicon.Graph.Node {

	func testNode<Path>(path: Path) throws -> Self
	where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			return self
		}
		guard let child = children[name] else {
			throw LexiconError("Missing child")
		}
		return try child.testNode(path: path.dropFirst())
	}
}

private func didThrow(_ body: () throws -> Void) -> Bool {
	do {
		try body()
		return false
	} catch {
		return true
	}
}

private func didThrow(_ body: () async throws -> Void) async -> Bool {
	do {
		try await body()
		return false
	} catch {
		return true
	}
}

private struct InvalidEmbeddingProvider: Lexicon.Search.EmbeddingProvider {

	enum Failure: CaseIterable, Sendable {
		case count
		case empty
		case inconsistentDimensions
		case descriptorDimension
		case nonFinite
	}

	var failure: Failure

	var descriptor: Lexicon.Search.EmbeddingDescriptor {
		.init(
			provider: "test",
			model: "invalid",
			tokenizer: "test",
			dimensions: failure == .descriptorDimension ? 3 : 2,
			normalized: false,
			pooling: "none"
		)
	}

	func embed(_ texts: [String]) async throws -> [[Double]] {
		switch failure {
			case .count:
				return []
			case .empty:
				return Array(repeating: [], count: texts.count)
			case .inconsistentDimensions:
				return texts.indices.map { $0 == texts.startIndex ? [1, 0] : [1] }
			case .descriptorDimension:
				return Array(repeating: [1, 0], count: texts.count)
			case .nonFinite:
				return Array(repeating: [.nan, 0], count: texts.count)
		}
	}
}

private extension String {

	func substring(utf16 range: Range<Int>) -> String? {
		guard
			let lower = utf16.index(
				utf16.startIndex,
				offsetBy: range.lowerBound,
				limitedBy: utf16.endIndex
			),
			let upper = utf16.index(
				utf16.startIndex,
				offsetBy: range.upperBound,
				limitedBy: utf16.endIndex
			),
			let start = String.Index(lower, within: self),
			let end = String.Index(upper, within: self)
		else {
			return nil
		}
		return String(self[start..<end])
	}
}
