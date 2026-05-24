//
// github.com/screensailor 2026
//

import Foundation

final class BranchPasteTests: Hopes {

	func test_branch_export_rewrites_internal_references_and_reports_external_references() async throws {

		let lexicon = try await Lexicon.from(TaskPaper("""
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
			""").decodeDocument())

		let branch = try await lexicon["root.branch"].hopefully()
		let exported = await branch.exportBranchDocument()

		hope(exported.diagnostics) == [
			.init(kind: .externalType, path: "branch.external", reference: "root.shared.kind"),
		]
		hope(exported.document.imports) == [.init("root")]
		hope(TaskPaper.encode(exported.document)) == """
			@ root
			branch:
				external:
				+ root.shared.kind
				item:
				? @ branch.kind
				+ branch.kind
				kind:
			"""
	}

	func test_paste_rewrites_branch_internal_references_at_destination() async throws {

		let lexicon = try await Lexicon.from(TaskPaper("""
			root:
				anchor:
				outside:
					type:
			""").decodeDocument())
		let branch = try TaskPaper("""
			branch:
				kind:
				item:
				+ branch.kind
				? @ branch.kind
				external:
				+ outside.type
			""").decodeDocument()
		hope(Array(branch.roots.keys)) == ["branch"]

		let anchor = try await lexicon["root.anchor"].hopefully()
		let result = await lexicon.paste(branch, to: anchor)
		let encoded = await TaskPaper.encode(lexicon.document)

		hope(result.lemmaID) == "root.anchor.branch"
		hope(result.diagnostics) == [
			.init(kind: .externalType, path: "branch.external", reference: "outside.type"),
		]
		hope(encoded) == """
			root:
				anchor:
					branch:
						external:
						+ outside.type
						item:
						? @ root.anchor.branch.kind
						+ root.anchor.branch.kind
						kind:
				outside:
					type:
			"""
	}
}
