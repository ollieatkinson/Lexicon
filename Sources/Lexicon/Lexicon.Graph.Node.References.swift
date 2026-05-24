//
// github.com/screensailor 2026
//

extension Lexicon.Graph.Node {

	func rewritingInternalReferences(
		from oldRootID: Lemma.ID,
		to newRootID: Lemma.ID,
		path: Lemma.ID,
		parentPath: Lemma.ID?,
		name newName: Name? = nil
	) -> Self {
		var node = self
		if let newName {
			node.name = newName
		}
		node.type = Set(node.type.map { $0.rewritingInternalReference(from: oldRootID, to: newRootID) })
		if case .reference(let reference) = node.defaultValue {
			node.defaultValue = .reference(reference.rewritingInternalReference(from: oldRootID, to: newRootID))
		}
		if let protonym = node.protonym {
			let rewritten = protonym.rewritingInternalReference(from: oldRootID, to: newRootID)
			node.protonym = parentPath.map { rewritten.dotPath(after: $0) } ?? rewritten
		}
		var children: Lexicon.Graph.Node.Children = [:]
		for (name, child) in node.children {
			let childPath = "\(path).\(name)"
			children[name] = child.rewritingInternalReferences(
				from: oldRootID,
				to: newRootID,
				path: childPath,
				parentPath: path,
				name: name
			)
		}
		node.children = children
		return node
	}
}

extension String {

	func rewritingInternalReference(from oldRootID: String, to newRootID: String) -> String {
		if self == oldRootID {
			return newRootID
		}
		guard hasPrefix("\(oldRootID).") else {
			return self
		}
		return "\(newRootID)\(dropFirst(oldRootID.count))"
	}
}

extension Array where Element: Hashable {

	func uniqued() -> [Element] {
		var seen: Set<Element> = []
		return filter { seen.insert($0).inserted }
	}
}
