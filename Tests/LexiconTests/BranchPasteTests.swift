//
// github.com/screensailor 2026
//

import Testing
import Foundation

#if EDITOR

@Suite

struct BranchPasteTests {

	@Test
	func test_branch_export_rewrites_internal_references_and_reports_external_references() async throws {

		let document = try TaskPaper("""
			root:
				shared:
					kind:
				branch:
					kind:
					item:
					+ root.branch.kind
					? @ root.branch.kind
					external:
					+ root.shared.kind
			""").decodeDocument()
		let lexicon = try await Lexicon(document: document, selectedRoot: "root")

		let branch = try #require(await lexicon["root.branch"])
		let exported = await branch.exportBranchDocument()

		#expect(exported.diagnostics == [
			.init(kind: .externalType, path: "branch.external", reference: "root.shared.kind"),
		])
		#expect(exported.document.imports == [.init("root")])
		#expect(TaskPaper.encode(exported.document) == """
			@ root
			branch:
				external:
				+ root.shared.kind
				item:
				? @ branch.kind
				+ branch.kind
				kind:
			""")
	}

	@Test
	func test_paste_rewrites_branch_internal_references_at_destination() async throws {

		let document = try TaskPaper("""
			root:
				anchor:
				outside:
					type:
			""").decodeDocument()
		let lexicon = try await Lexicon(document: document, selectedRoot: "root")
		let branch = try TaskPaper("""
			branch:
				kind:
				item:
				+ branch.kind
				? @ branch.kind
				external:
				+ root.outside.type
			""").decodeDocument()
		#expect(Array(branch.roots.keys) == ["branch"])

		let anchor = try #require(await lexicon["root.anchor"])
		let result = try await lexicon.paste(branch, root: "branch", to: anchor)
		let encoded = await TaskPaper.encode(lexicon.document)

		#expect(result.lemmaID == "root.anchor.branch")
		#expect(result.diagnostics == [
			.init(kind: .externalType, path: "branch.external", reference: "root.outside.type"),
		])
		#expect(encoded == """
			root:
				anchor:
					branch:
						external:
						+ root.outside.type
						item:
						? @ root.anchor.branch.kind
						+ root.anchor.branch.kind
						kind:
				outside:
					type:
			""")
	}
}

#endif
