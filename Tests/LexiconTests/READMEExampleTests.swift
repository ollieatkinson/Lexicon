//
// github.com/screensailor 2026
//

import Foundation
import Hope
@testable import Lexicon

final class READMEExampleTests: Hopes {

	func test_readme_commerce_example_composes() async throws {

		let examples = try Self.taskpaperExamples()
		let baseURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconREADMEExamples-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: baseURL) }

		try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
		for (filename, source) in examples {
			try Data(source.utf8).write(to: baseURL.appendingPathComponent(filename))
		}

		let source = baseURL.appendingPathComponent("commerce.lexicon")
		let document = try TaskPaper(Data(contentsOf: source)).decodeDocument()

		hope(document.comments) == ["Commerce language shared by API, UI, session and product surfaces."]
		hope(document.notes) == ["Product teams can add local dialects without replacing the shared vocabulary."]
		hope(document.imports) == [.init("./shared-commerce.lexicon")]
		hope(Array(document.roots.keys)) == ["commerce", "support"]

		let supportStatus = try document.roots["support"].try().child("case.status")
		hope(supportStatus.type) == ["commerce.db.type.string"]
		hope(supportStatus.defaultValue) == .literal(.string("open"))

		let plan = try document.composed(resolving: FileLexiconImportResolver(baseURL: baseURL))

		hope(plan.conflicts) == []
		hope(Array(plan.document.roots.keys)) == ["commerce"]

		let commerce = try plan.document.roots["commerce"].try()
		hope(commerce.notes) == ["Terms under this root are composed into generated platform code."]
		hope(Array(commerce.children.keys)) == ["api", "db", "session", "support", "ui", "ux"]

		let product = try commerce.child("api.storefront.products.product")
		hope(product.type) == ["commerce.db.collection"]

		let eligible = try commerce.child("api.storefront.products.product.is.eligible")
		hope(eligible.type) == [
			"commerce.db.type.boolean",
			"commerce.session.state.value",
		]

		let submit = try commerce.child("api.storefront.order.create.can.submit")
		hope(submit.type) == [
			"commerce.db.type.boolean",
			"commerce.session.configuration.value",
		]

		let primaryAction = try commerce.child("api.storefront.order.create.primary.action")
		hope(primaryAction.type) == [
			"commerce.ui.type.button.primary",
			"commerce.ux.type.action",
		]

		let enabled = try commerce.child("ui.product.card.buy.enabled")
		hope(enabled.type) == ["commerce.api.storefront.order.create.can.submit"]
		hope(enabled.defaultValue) == .literal(.bool(true))

		let active = try commerce.child("ui.product.card.buy.active")
		hope(active.protonym) == "enabled"

		let composedSupportStatus = try commerce.child("support.case.status")
		hope(composedSupportStatus.type) == ["commerce.db.type.string"]
		hope(composedSupportStatus.defaultValue) == .literal(.string("open"))

		let lexicon = try await Lexicon.from(plan.document, root: "commerce")
		let enabledLemma = try await lexicon["commerce.ui.product.card.buy.enabled"].hopefully()
		let submitLemma = try await lexicon["commerce.api.storefront.order.create.can.submit"].hopefully()
		let enabledDefault = await enabledLemma.defaultValue
		let enabledIsSubmitCapability = await enabledLemma.is(submitLemma)
		let json = await lexicon.json()

		hope(enabledDefault) == .literal(.bool(true))
		hope(enabledIsSubmitCapability) == true

		let rootJSON = try json.classes.first { $0.id == "commerce" }.try()
		let enabledJSON = try json.classes.first { $0.id == "commerce.ui.product.card.buy.enabled" }.try()
		let buyJSON = try json.classes.first { $0.id == "commerce.ui.product.card.buy" }.try()

		hope(rootJSON.notes) == ["Terms under this root are composed into generated platform code."]
		hope(enabledJSON.defaultValue) == DefaultValueJSON(.literal(.bool(true)))
		hope(buyJSON.synonyms) == ["active": "enabled"]
	}

	func test_readme_swift_examples_use_generated_member_access() throws {

		let readme = try Self.readme()

		hope.false(readme.contains("lexicon[\""))
		hope.true(readme.contains("commerce.api.storefront.order.create.can.submit"))
		hope.true(readme.contains("commerce.ui.product.card.buy.enabled"))

		for filename in Self.connectedExampleFilenames {
			hope.true(readme.contains("<summary><code>\(filename)</code></summary>"))
		}
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

	static func taskpaperExamples() throws -> [String: String] {
		let readme = try readme()
		let filenames = [mainExampleFilename] + connectedExampleFilenames
		return try Dictionary(uniqueKeysWithValues: filenames.map { filename in
			try (filename, taskpaperExample(named: filename, in: readme))
		})
	}

	static func taskpaperExample(named filename: String, in readme: String) throws -> String {
		let marker = filename == mainExampleFilename
			? "`\(filename)`"
			: "<summary><code>\(filename)</code></summary>"
		guard let markerRange = readme.range(of: marker) else {
			throw "README example marker not found: \(filename)"
		}

		let tail = readme[markerRange.upperBound...]
		guard let fenceStart = tail.range(of: "```taskpaper\n") else {
			throw "README TaskPaper fence not found: \(filename)"
		}

		let content = tail[fenceStart.upperBound...]
		guard let fenceEnd = content.range(of: "\n```") else {
			throw "README TaskPaper fence end not found: \(filename)"
		}

		return String(content[..<fenceEnd.lowerBound])
	}

	static func readme() throws -> String {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		return try String(
			contentsOf: root.appendingPathComponent("README.md"),
			encoding: .utf8
		)
	}
}

private extension Lexicon.Graph.Node {

	func child(_ path: String) throws -> Self {
		try path.split(separator: ".").reduce(self) { node, component in
			try node.children[String(component)].try()
		}
	}
}

private typealias DefaultValueJSON = Lexicon.Graph.Node.DefaultValue.JSON
