//
// github.com/screensailor 2026
//

extension Lexicon.Graph.Node {

	func rewritingInternalReferences(
		from oldRootID: Lemma.ID,
		to newRootID: Lemma.ID,
		oldPath: Lemma.ID,
		newPath: Lemma.ID
	) -> Self {
		var node = self
		node.type = Set(node.type.map {
			$0.rewritingInternalReference(from: oldRootID, to: newRootID)
		})
		if case .reference(let reference) = node.defaultValue {
			node.defaultValue = .reference(
				reference.rewritingInternalReference(from: oldRootID, to: newRootID)
			)
		}
		if
			let protonym = node.protonym,
			let oldParent = oldPath.parent,
			let newParent = newPath.parent
		{
			let oldTarget = oldParent.appending(protonym)
			if oldTarget.isInLineage(of: oldRootID) {
				let target = oldTarget.rewritingInternalReference(
					from: oldRootID,
					to: newRootID
				)
				node.protonym = try! target.relative(to: newParent)
			}
		}
		for (name, child) in node.children {
			node.children[name] = child.rewritingInternalReferences(
				from: oldRootID,
				to: newRootID,
				oldPath: oldPath.appending(name),
				newPath: newPath.appending(name)
			)
		}
		return node
	}
}

extension Lemma.ID {

	func rewritingInternalReference(
		from oldRootID: Self,
		to newRootID: Self
	) -> Self {
		guard isInLineage(of: oldRootID) else {
			return self
		}
		return try! Self(
			components: newRootID.components + components.dropFirst(oldRootID.components.count)
		)
	}
}

extension Array where Element: Hashable {

	func uniqued() -> [Element] {
		var seen: Set<Element> = []
		return filter { seen.insert($0).inserted }
	}
}
