//
// github.com/screensailor 2026
//

import Testing
import Foundation
@testable import Lexicon

@Suite

struct READMEExampleTests {

	@Test
	func test_readme_commerce_example_composes() async throws {

		let examples = try Self.resourceExamples()
		let baseURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconREADMEExamples-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: baseURL) }

		try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
		for (filename, source) in examples {
			try Data(source.utf8).write(to: baseURL.appendingPathComponent(filename))
		}

		let source = baseURL.appendingPathComponent("commerce.lexicon")
		let document = try TaskPaper(Data(contentsOf: source)).decodeDocument()

		#expect(document.comments == ["Commerce language shared by API, UI, session and product surfaces."])
		#expect(document.notes == ["Product teams can add local dialects without replacing the shared vocabulary."])
		#expect(document.imports == [.init("./shared-commerce.lexicon")])
		#expect(Array(document.roots.keys) == ["commerce", "support"])

		let supportStatus = try document.roots["support"].try().child("case.status")
		#expect(supportStatus.type == ["commerce.db.type.string"])
		#expect(supportStatus.defaultValue == .literal(.string("open")))

		let plan = try document.composed(resolving: FileLexiconImportResolver(baseURL: baseURL))

		#expect(plan.conflicts == [])
		#expect(Array(plan.document.roots.keys) == ["commerce"])

		let commerce = try plan.document.roots["commerce"].try()
		#expect(commerce.notes == ["Terms under this root are composed into generated platform code."])
		#expect(Array(commerce.children.keys) == ["api", "db", "session", "support", "ui", "ux"])

		let product = try commerce.child("api.storefront.products.product")
		#expect(product.type == ["commerce.db.collection"])

		let eligible = try commerce.child("api.storefront.products.product.is.eligible")
		#expect(eligible.type == [
			"commerce.db.type.boolean",
			"commerce.session.state.value",
		])

		let submit = try commerce.child("api.storefront.order.create.can.submit")
		#expect(submit.type == [
			"commerce.db.type.boolean",
			"commerce.session.configuration.value",
		])

		let primaryAction = try commerce.child("api.storefront.order.create.primary.action")
		#expect(primaryAction.type == [
			"commerce.ui.type.button.primary",
			"commerce.ux.type.action",
		])

		let enabled = try commerce.child("ui.product.card.buy.enabled")
		#expect(enabled.type == ["commerce.api.storefront.order.create.can.submit"])
		#expect(enabled.defaultValue == .literal(.bool(true)))

		let active = try commerce.child("ui.product.card.buy.active")
		#expect(active.protonym == "enabled")

		let composedSupportStatus = try commerce.child("support.case.status")
		#expect(composedSupportStatus.type == ["commerce.db.type.string"])
		#expect(composedSupportStatus.defaultValue == .literal(.string("open")))

		let lexicon = try await Lexicon.from(plan.document, root: "commerce")
		let enabledLemma = try #require(await lexicon["commerce.ui.product.card.buy.enabled"])
		let submitLemma = try #require(await lexicon["commerce.api.storefront.order.create.can.submit"])
		let enabledDefault = await enabledLemma.defaultValue
		let enabledIsSubmitCapability = await enabledLemma.is(submitLemma)
		let json = await lexicon.json()

		#expect(enabledDefault == .literal(.bool(true)))
		#expect(enabledIsSubmitCapability == true)

		let rootJSON = try json.classes.first { $0.id == "commerce" }.try()
		let enabledJSON = try json.classes.first { $0.id == "commerce.ui.product.card.buy.enabled" }.try()
		let buyJSON = try json.classes.first { $0.id == "commerce.ui.product.card.buy" }.try()

		#expect(rootJSON.notes == ["Terms under this root are composed into generated platform code."])
		#expect(enabledJSON.defaultValue == DefaultValueJSON(.literal(.bool(true))))
		#expect(buyJSON.synonyms == ["active": "enabled"])
	}

	@Test
	func test_readme_links_to_wiki_and_keeps_generated_member_access_example() throws {

		guard let readme = try Self.readmeIfAvailable() else {
			return
		}

		#expect(!(readme.contains("lexicon[\"")))
		#expect(readme.contains("commerce.api.order.submit"))
		#expect(readme.contains("commerce.ui.checkout.button.primary"))
		#expect(readme.contains("https://github.com/ollieatkinson/Lexicon/wiki/Quick-Start"))
		#expect(readme.contains("https://github.com/ollieatkinson/Lexicon/wiki/Gardening-Philosophy"))
		#expect(readme.contains("https://github.com/ollieatkinson/Lexicon/wiki/Example-Commerce-Vocabulary"))
		#expect(readme.contains("https://github.com/ollieatkinson/Lexicon/wiki/Editor-Support"))
	}
}

private extension READMEExampleTests {

	static let mainExampleFilename = "commerce.lexicon"
	static let connectedExampleFilenames = [
		"shared-commerce.lexicon",
		"data-types.lexicon",
		"storefront-api.lexicon",
		"product-ui.lexicon",
	]

	static func resourceExamples() throws -> [String: String] {
		let filenames = [mainExampleFilename] + connectedExampleFilenames
		return try Dictionary(uniqueKeysWithValues: filenames.map { filename in
			try (filename, resourceExample(named: filename))
		})
	}

	static func resourceExample(named filename: String) throws -> String {
		guard let url = Bundle.module.url(
			forResource: "Resources/READMEExamples/\(filename)",
			withExtension: nil
		) else {
			throw "README example resource not found: \(filename)"
		}
		return try String(contentsOf: url, encoding: .utf8).droppingTrailingNewline()
	}

	static func readmeIfAvailable() throws -> String? {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let url = root.appendingPathComponent("README.md")
		guard FileManager.default.fileExists(atPath: url.path) else {
			return nil
		}
		return try String(contentsOf: url, encoding: .utf8)
	}
}

private extension Lexicon.Graph.Node {

	func child(_ path: String) throws -> Self {
		try path.split(separator: ".").reduce(self) { node, component in
			try node.children[String(component)].try()
		}
	}
}

private extension String {

	func droppingTrailingNewline() -> String {
		hasSuffix("\n") ? String(dropLast()) : self
	}
}

private typealias DefaultValueJSON = Lexicon.Graph.Node.DefaultValue.JSON
