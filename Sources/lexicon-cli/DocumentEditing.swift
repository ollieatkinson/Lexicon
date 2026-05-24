import ArgumentParser
import Foundation
import Lexicon

extension Lexicon.Document {

	func lemma(_ id: String) async throws -> Lemma {
		let root = try rootName(for: id)
		let lexicon = try await Lexicon.from(self, root: root)
		guard let lemma = await lexicon[id] else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		return lemma
	}

	var validationDiagnostics: [AgentDiagnostic] {
		var diagnostics: [AgentDiagnostic] = []
		var index: Set<String> = []
		var nodes: [(id: String, node: Lexicon.Graph.Node)] = []

		for root in roots.values {
			root.traverse { id, _, node in
				index.insert(id)
				nodes.append((id, node))
			}
		}

		for (id, node) in nodes {
			if !Lemma.isValid(name: node.name) {
				diagnostics.append(.init(
					severity: "error",
					kind: "invalidName",
					path: id,
					reference: nil,
					message: "Invalid lemma name '\(node.name)'."
				))
			}

			for type in node.type.sorted() where !index.contains(type) {
				diagnostics.append(.init(
					severity: "error",
					kind: "unresolvedType",
					path: id,
					reference: type,
					message: "Type reference '\(type)' does not resolve in this document."
				))
			}

			if let protonym = node.protonym, !index.resolves(protonym, fromParentOf: id) {
				diagnostics.append(.init(
					severity: "error",
					kind: "unresolvedProtonym",
					path: id,
					reference: protonym,
					message: "Protonym reference '\(protonym)' does not resolve from '\(id)'."
				))
			}

			if case .reference(let reference) = node.defaultValue, !index.resolves(reference, fromParentOf: id) {
				diagnostics.append(.init(
					severity: "error",
					kind: "unresolvedDefault",
					path: id,
					reference: reference,
					message: "Default reference '\(reference)' does not resolve from '\(id)'."
				))
			}
		}

		return diagnostics.sorted {
			($0.path, $0.kind, $0.reference ?? "") < ($1.path, $1.kind, $1.reference ?? "")
		}
	}

	var lintDiagnostics: [AgentDiagnostic] {
		var diagnostics = validationDiagnostics
		let index = nodeIndex()
		let ids = Set(index.keys)
		let importedReferences = Set(imports.map(\.reference))

		for (id, node) in index.sorted(by: { $0.key < $1.key }) {
			if node.protonym != nil && (node.children.isNotEmpty || node.type.isNotEmpty) {
				diagnostics.append(.init(
					severity: "warning",
					kind: "synonymCarriesDefinition",
					path: id,
					reference: node.protonym,
					message: "Synonym node '\(id)' also declares children or types."
				))
			}
			for reference in references(from: id, index: ids) where !reference.exists {
				let root = reference.reference.components(separatedBy: ".").first ?? reference.reference
				if !importedReferences.contains(root) && !importedReferences.contains(reference.reference) {
					diagnostics.append(.init(
						severity: "warning",
						kind: "externalReferenceWithoutImport",
						path: id,
						reference: reference.reference,
						message: "Reference '\(reference.reference)' does not resolve locally and no matching import is declared."
					))
				}
			}
		}

		return diagnostics.sorted {
			($0.severity, $0.path, $0.kind, $0.reference ?? "") <
			($1.severity, $1.path, $1.kind, $1.reference ?? "")
		}
	}

	func firstRootID() throws -> String {
		guard let id = roots.keys.first else {
			throw ValidationError("The document does not declare a root lemma.")
		}
		return String(id)
	}

	func nodeIndex() -> [String: Lexicon.Graph.Node] {
		var index: [String: Lexicon.Graph.Node] = [:]
		for root in roots.values {
			root.traverse { id, _, node in
				index[id] = node
			}
		}
		return index
	}

	func node(_ id: String) throws -> Lexicon.Graph.Node {
		let components = id.pathComponents
		guard let rootName = components.first, let root = roots[rootName] else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		return try root.node(path: components.dropFirst())
	}

	func ownTree(id: String, depth: Int, metadata: Bool) throws -> TreeNode {
		try TreeNode.own(id: id, node: node(id), depth: max(0, depth), metadata: metadata)
	}

	func references(from id: String, index: Set<String>) -> [ReferenceUse] {
		guard let node = try? node(id) else {
			return []
		}
		var references: [ReferenceUse] = []
		func append(kind: String, reference: String) {
			let resolved = reference.resolved(fromParentOf: id, in: index)
			references.append(.init(
				kind: kind,
				path: id,
				reference: reference,
				resolved: resolved,
				exists: resolved != nil
			))
		}
		for type in node.type.sorted() {
			append(kind: "type", reference: type)
		}
		if let protonym = node.protonym {
			append(kind: "protonym", reference: protonym)
		}
		if case .reference(let reference) = node.defaultValue {
			append(kind: "default", reference: reference)
		}
		return references.sorted {
			($0.kind, $0.reference) < ($1.kind, $1.reference)
		}
	}

	mutating func updateNode(_ id: String, _ body: (inout Lexicon.Graph.Node) throws -> Void) throws {
		let components = id.pathComponents
		guard let rootName = components.first, roots[rootName] != nil else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		try roots.mutate(rootName) { root in
			try root.mutate(path: components.dropFirst(), body: body)
		}
	}

	mutating func rename(_ id: String, to newName: String) throws {
		guard Lemma.isValid(name: newName) else {
			throw ValidationError("Invalid lemma name: \(newName)")
		}
		let components = id.pathComponents
		guard let rootName = components.first, roots[rootName] != nil else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		let oldIndex = Set(nodeIndex().keys)
		let newID = (components.dropLast() + [newName]).joined(separator: ".")
		if components.count == 1 {
			guard roots[newName] == nil else {
				throw ValidationError("Root '\(newName)' already exists.")
			}
			var root = roots.removeValue(forKey: rootName)!
			root.name = newName
			roots[newName] = root
		} else {
			let parentPath = components.dropFirst().dropLast()
			let oldName = components.last!
			try roots.mutate(rootName) { root in
				try root.mutate(path: parentPath) { parent in
					guard parent.children[newName] == nil else {
						throw ValidationError("Parent already has a child named '\(newName)'.")
					}
					guard var node = parent.children.removeValue(forKey: oldName) else {
						throw ValidationError("Could not find lemma: \(id)")
					}
					node.name = newName
					parent.children[newName] = node
				}
			}
		}
		rewriteReferences(from: id, to: newID, resolvingIn: oldIndex)
	}

	mutating func move(_ id: String, under parentID: String) throws {
		let components = id.pathComponents
		guard let name = components.last else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		guard !parentID.isSameOrDescendant(of: id) else {
			throw ValidationError("Cannot move '\(id)' under its own descendant '\(parentID)'.")
		}
		let oldIndex = Set(nodeIndex().keys)
		var node = try take(id)
		node.name = name
		try updateNode(parentID) { parent in
			guard parent.children[name] == nil else {
				throw ValidationError("Destination '\(parentID)' already has a child named '\(name)'.")
			}
			parent.children[name] = node
		}
		rewriteReferences(from: id, to: "\(parentID).\(name)", resolvingIn: oldIndex)
	}

	mutating func add(_ node: Lexicon.Graph.Node, under parentID: String) throws {
		guard !roots.isEmpty else {
			throw ValidationError("The document has no roots.")
		}
		let components = parentID.pathComponents
		guard let rootName = components.first, roots[rootName] != nil else {
			throw ValidationError("Could not find parent: \(parentID)")
		}
		try roots.mutate(rootName) { root in
			try root.mutate(path: components.dropFirst()) { parent in
				guard parent.children[node.name] == nil else {
					throw ValidationError("Parent '\(parentID)' already has a child named '\(node.name)'.")
				}
				parent.children[node.name] = node
			}
		}
	}

	mutating func remove(_ id: String) throws {
		let components = id.pathComponents
		guard let rootName = components.first, roots[rootName] != nil else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		guard components.count > 1 else {
			roots.removeValue(forKey: rootName)
			return
		}
		let name = components.last!
		try roots.mutate(rootName) { root in
			try root.mutate(path: components.dropFirst().dropLast()) { parent in
				guard parent.children.removeValue(forKey: name) != nil else {
					throw ValidationError("Could not find lemma: \(id)")
				}
			}
		}
	}

	private mutating func take(_ id: String) throws -> Lexicon.Graph.Node {
		let components = id.pathComponents
		guard let rootName = components.first, roots[rootName] != nil else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		guard components.count > 1 else {
			return roots.removeValue(forKey: rootName)!
		}
		let name = components.last!
		var removed: Lexicon.Graph.Node?
		try roots.mutate(rootName) { root in
			try root.mutate(path: components.dropFirst().dropLast()) { parent in
				removed = parent.children.removeValue(forKey: name)
			}
		}
		guard let removed else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		return removed
	}

	private mutating func rewriteReferences(from oldID: String, to newID: String, resolvingIn ids: Set<String>) {
		for rootName in roots.keys {
			roots[rootName]?.rewriteReferences(
				path: String(rootName),
				index: ids,
				from: oldID,
				to: newID
			)
		}
	}

	private func rootName(for id: String) throws -> String {
		let name = id.pathComponents.first ?? id
		guard roots[name] != nil else {
			throw ValidationError("Could not find root for lemma ID: \(id)")
		}
		return name
	}
}

extension Lexicon.Graph.Node {

	func node<Path>(path: Path) throws -> Self where Path: Collection, Path.Element == String {
		guard let name = path.first else {
			return self
		}
		guard let child = children[name] else {
			throw ValidationError("Could not find lemma path component: \(name)")
		}
		return try child.node(path: path.dropFirst())
	}

	mutating func mutate<Path>(
		path: Path,
		body: (inout Self) throws -> Void
	) throws where Path: Collection, Path.Element == String {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw ValidationError("Could not find lemma path component: \(name)")
		}
		try child.mutate(path: path.dropFirst(), body: body)
		children[name] = child
	}

	mutating func rewriteReferences(path: String, index: Set<String>, from oldID: String, to newID: String) {
		type = Set(type.map { $0.rewritingReference(from: oldID, to: newID, at: path, index: index) })
		protonym = protonym?.rewritingReference(from: oldID, to: newID, at: path, index: index)
		if case .reference(let reference) = defaultValue {
			defaultValue = .reference(reference.rewritingReference(from: oldID, to: newID, at: path, index: index))
		}
		for name in children.keys {
			children[name]?.rewriteReferences(path: "\(path).\(name)", index: index, from: oldID, to: newID)
		}
	}
}

extension Lexicon.Graph.Node.DefaultValue {

	static func parseAgentArgument(_ string: String) -> Self {
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("@") {
			return .reference(trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines))
		}
		return .literal(.parse(trimmed))
	}
}

