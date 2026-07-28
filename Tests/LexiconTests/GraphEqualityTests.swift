//
// github.com/screensailor 2026
//

import Foundation
import Testing
@testable import Lexicon

@Suite
struct GraphEqualityTests {

	@Test
	func equality_compares_root_structure() {
		let date = Date(timeIntervalSinceReferenceDate: 0)
		var leftRoot = Lexicon.Graph.Node()
		var rightRoot = Lexicon.Graph.Node()

		leftRoot.make(child: "left")
		rightRoot.make(child: "right")

		let left = Lexicon.Graph(rootName: "root", root: leftRoot, date: date)
		let right = Lexicon.Graph(rootName: "root", root: rightRoot, date: date)

		#expect(left != right)
	}

	@Test
	func node_traverse_derives_ids_from_path_components() {
		let root = Lexicon.Graph.Node(
			children: [
				"child": .init(
					children: [
						"leaf": .init()
					]
				)
			]
		)

		var ids: [Lemma.ID] = []
		root.traverse(id: "root") { item in
			ids.append(item.id)
		}

		#expect(ids == ["root", "root.child", "root.child.leaf"])
	}

	@Test
	func node_traverse_uses_storage_keys_for_child_paths() {
		let root = Lexicon.Graph.Node(
			children: [
				"child": .init(
					children: [
						"leaf": .init()
					]
				)
			]
		)

		var ids: [Lemma.ID] = []
		root.traverse(id: "root") { item in
			ids.append(item.id)
		}

		#expect(ids == ["root", "root.child", "root.child.leaf"])
	}
}
