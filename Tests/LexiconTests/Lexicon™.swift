//
// github.com/screensailor 2021
//
import Testing
@_exported import Lexicon

@Suite

struct Lexicon™ {
	
	@Test
	func test() async throws {
		
		let lexicon = try await Lexicon.from(TaskPaper(taskpaper).decode())
		let root = await lexicon.root
		var cli = await CLI(root)
		
		#expect(cli.suggestions.map(\.name) == ["idea", "purpose", "type", "ui", "ux"])
		
		await cli.replace(input: "idea")
		await cli.enter()
		
		#expect(cli.suggestions.map(\.name) == ["knowledge"])
		
		let mindMap = try #require(await lexicon["root.idea.knowledge.mind_map"])
		let tree = try #require(await lexicon["root.idea.knowledge.tree"])
		
		#expect(await mindMap.source == tree)
		#expect(await mindMap.source === tree)
		
		// TODO: ...
	}
}

private let taskpaper = """
root:
	idea:
		knowledge:
			directory:
			= tree
			mind_map:
			= tree
			outline:
			= tree
			tree:
				branch:
				+ root.idea.knowledge.tree
				leaf:
	purpose:
		lexicon:
			lemma:
		vocabulary:
		= lexicon
	type:
		ux:
			journey:
				entry:
				+ root.ui.view.control
	ui:
		placeable:
			placed:
				above:
				+ root.ux
				below:
				+ root.ux
		view:
			control:
				button:
				+ root.ui.placeable
			label:
			+ root.ui.placeable
	ux:
		menu:
			File:
				New:
				+ root.type.ux.journey
				Open:
				+ root.type.ux.journey
					json:
					taskpaper:
"""
