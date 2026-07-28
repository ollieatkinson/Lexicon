import ArgumentParser
import Foundation
import Lexicon

extension Lexicon.Document {

	@LexiconActor
	func lemma(_ rawID: String) throws -> Lemma {
		let id = try Lemma.ID(parsing: rawID)
		let lexicon = try Lexicon(document: self, selectedRoot: id.root)
		guard let lemma = lexicon[id] else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		return lemma
	}

	var validationDiagnostics: [AgentDiagnostic] {
		validate().map(AgentDiagnostic.init)
	}

	var lintDiagnostics: [AgentDiagnostic] {
		var diagnostics = validationDiagnostics
		let index = nodeIndex()
		let ids = Set(index.keys)
		let importedReferences = Set(imports.map(\.reference))

		for id in index.keys.sorted() {
			for reference in references(from: id, index: ids) where !reference.exists {
				let root = reference.reference.split(separator: ".").first.map(String.init)
					?? reference.reference
				if !importedReferences.contains(root) &&
					!importedReferences.contains(reference.reference)
				{
					diagnostics.append(.init(
						severity: "warning",
						kind: "externalReferenceWithoutImport",
						path: id.description,
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
		guard roots.count == 1, let name = roots.keys.first else {
			if roots.isEmpty {
				throw ValidationError("The document does not declare a root lemma.")
			}
			throw ValidationError("The document declares multiple roots; provide an explicit lemma ID.")
		}
		return Lemma.ID(root: name).description
	}

	func nodeIndex() -> [Lemma.ID: Lexicon.Graph.Node] {
		var index: [Lemma.ID: Lexicon.Graph.Node] = [:]
		for (name, root) in roots {
			root.traverse(id: Lemma.ID(root: name)) { item in
				index[item.id] = item.node
			}
		}
		return index
	}

	func node(_ rawID: String) throws -> Lexicon.Graph.Node {
		try declaredNode(Lemma.ID(parsing: rawID))
	}

	func ownTree(id rawID: String, depth: Int, metadata: Bool) throws -> TreeNode {
		let id = try Lemma.ID(parsing: rawID)
		return try TreeNode.own(
			id: id,
			node: declaredNode(id),
			depth: max(0, depth),
			metadata: metadata
		)
	}

	func references(from rawID: String, index: Set<Lemma.ID>) -> [ReferenceUse] {
		guard let id = try? Lemma.ID(parsing: rawID) else {
			return []
		}
		return references(from: id, index: index)
	}

	func references(from id: Lemma.ID, index: Set<Lemma.ID>) -> [ReferenceUse] {
		guard let node = try? declaredNode(id) else {
			return []
		}
		var references: [ReferenceUse] = []
		func append(kind: String, reference: String, resolved: Lemma.ID?) {
			references.append(.init(
				kind: kind,
				path: id.description,
				reference: reference,
				resolved: resolved?.description,
				exists: resolved != nil
			))
		}
		for type in node.type.sorted() {
			append(
				kind: "type",
				reference: type.description,
				resolved: index.contains(type) ? type : nil
			)
		}
		if let protonym = node.protonym, let parent = id.parent {
			let target = parent.appending(protonym)
			append(
				kind: "protonym",
				reference: protonym.description,
				resolved: index.contains(target) ? target : nil
			)
		}
		if case .reference(let reference) = node.defaultValue {
			append(
				kind: "default",
				reference: reference.description,
				resolved: index.contains(reference) ? reference : nil
			)
		}
		return references.sorted {
			($0.kind, $0.reference) < ($1.kind, $1.reference)
		}
	}

	mutating func updateNode(
		_ rawID: String,
		sourceURL: URL,
		_ body: (inout Lexicon.Graph.Node) throws -> Void
	) throws {
		let id = try Lemma.ID(parsing: rawID)
		try transaction(sourceURL: sourceURL) { document in
			try document.mutateDeclaredNode(id, body)
		}
	}

	mutating func rename(
		_ rawID: String,
		to rawName: String,
		sourceURL: URL
	) throws {
		let id = try Lemma.ID(parsing: rawID)
		let name = try Lemma.Name(validating: rawName)
		let newID = id.parent?.appending(name) ?? Lemma.ID(root: name)
		guard newID != id else {
			throw ValidationError("Lemma '\(id)' already has name '\(name)'.")
		}

		try transaction(sourceURL: sourceURL) { document in
			let references = try document.referenceSnapshot()
			if let parentID = id.parent {
				try document.mutateDeclaredNode(parentID) { parent in
					guard parent.children[name] == nil else {
						throw ValidationError("Lemma '\(newID)' already exists.")
					}
					guard let node = parent.children.removeValue(forKey: id.name) else {
						throw ValidationError("Could not find lemma: \(id)")
					}
					parent.children[name] = node
				}
			} else {
				guard document.roots[name] == nil else {
					throw ValidationError("Root '\(name)' already exists.")
				}
				guard let root = document.roots.removeValue(forKey: id.root) else {
					throw ValidationError("Could not find root: \(id)")
				}
				document.roots[name] = root
			}
			try document.rewriteReferences(references, from: id, to: newID)
		}
	}

	mutating func move(
		_ rawID: String,
		under rawParentID: String,
		sourceURL: URL
	) throws {
		let id = try Lemma.ID(parsing: rawID)
		let parentID = try Lemma.ID(parsing: rawParentID)
		guard !parentID.isInLineage(of: id) else {
			throw ValidationError("Cannot move '\(id)' under its own descendant '\(parentID)'.")
		}
		let newID = parentID.appending(id.name)

		try transaction(sourceURL: sourceURL) { document in
			let references = try document.referenceSnapshot()
			let node = try document.takeDeclaredNode(id)
			try document.mutateDeclaredNode(parentID) { parent in
				guard parent.children[id.name] == nil else {
					throw ValidationError("Lemma '\(newID)' already exists.")
				}
				parent.children[id.name] = node
			}
			try document.rewriteReferences(references, from: id, to: newID)
		}
	}

	mutating func add(
		_ node: Lexicon.Graph.Node,
		named rawName: String,
		under rawParentID: String,
		sourceURL: URL
	) throws {
		let name = try Lemma.Name(validating: rawName)
		let parentID = try Lemma.ID(parsing: rawParentID)
		let id = parentID.appending(name)
		try transaction(sourceURL: sourceURL) { document in
			try document.mutateDeclaredNode(parentID) { parent in
				guard parent.protonym == nil else {
					throw ValidationError("Cannot add a child to synonym '\(parentID)'.")
				}
				guard parent.children[name] == nil else {
					throw ValidationError("Lemma '\(id)' already exists.")
				}
				parent.children[name] = node
			}
		}
	}

	mutating func remove(_ rawID: String, sourceURL: URL) throws {
		let id = try Lemma.ID(parsing: rawID)
		try transaction(sourceURL: sourceURL) { document in
			guard document.roots.count > 1 || id.parent != nil else {
				throw ValidationError("Cannot delete the document's last root.")
			}
			let references = try document.referenceSnapshot()
			for (owner, snapshot) in references where !owner.isInLineage(of: id) {
				let referenced = snapshot.type.contains { $0.isInLineage(of: id) } ||
					snapshot.protonym?.isInLineage(of: id) == true ||
					snapshot.defaultReference?.isInLineage(of: id) == true
				guard !referenced else {
					throw ValidationError(
						"Cannot delete '\(id)' because '\(owner)' references its subtree."
					)
				}
			}
			_ = try document.takeDeclaredNode(id)
		}
	}

	private mutating func transaction(
		sourceURL: URL,
		_ body: (inout Lexicon.Document) throws -> Void
	) throws {
		var candidate = self
		try body(&candidate)
		candidate.date = Date()
		let plan = try candidate.composed(resolving: FileLexiconImportResolver(
			baseURL: sourceURL.deletingLastPathComponent(),
			rootURL: sourceURL
		))
		guard plan.conflicts.isEmpty else {
			throw ValidationError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		_ = try plan.document.validated()
		self = candidate
	}
}

private extension Lexicon.Document {

	struct CLIReferenceSnapshot {
		var type: Set<Lemma.ID>
		var protonym: Lemma.ID?
		var defaultReference: Lemma.ID?
	}

	func declaredNode(_ id: Lemma.ID) throws -> Lexicon.Graph.Node {
		guard let root = roots[id.root] else {
			throw ValidationError("Could not find root: \(id.root)")
		}
		return try root.cliNode(path: id.components.dropFirst())
	}

	mutating func mutateDeclaredNode(
		_ id: Lemma.ID,
		_ body: (inout Lexicon.Graph.Node) throws -> Void
	) throws {
		guard var root = roots[id.root] else {
			throw ValidationError("Could not find root: \(id.root)")
		}
		try root.cliMutate(path: id.components.dropFirst(), body)
		roots[id.root] = root
	}

	mutating func takeDeclaredNode(_ id: Lemma.ID) throws -> Lexicon.Graph.Node {
		guard let parent = id.parent else {
			guard let root = roots.removeValue(forKey: id.root) else {
				throw ValidationError("Could not find root: \(id)")
			}
			return root
		}
		var removed: Lexicon.Graph.Node?
		try mutateDeclaredNode(parent) {
			removed = $0.children.removeValue(forKey: id.name)
		}
		guard let removed else {
			throw ValidationError("Could not find lemma: \(id)")
		}
		return removed
	}

	func referenceSnapshot() throws -> [Lemma.ID: CLIReferenceSnapshot] {
		var result: [Lemma.ID: CLIReferenceSnapshot] = [:]
		for (id, node) in nodeIndex() {
			let protonym = node.protonym.flatMap { relative in
				id.parent?.appending(relative)
			}
			let defaultReference: Lemma.ID?
			if case .reference(let reference) = node.defaultValue {
				defaultReference = reference
			} else {
				defaultReference = nil
			}
			result[id] = .init(
				type: node.type,
				protonym: protonym,
				defaultReference: defaultReference
			)
		}
		return result
	}

	mutating func rewriteReferences(
		_ references: [Lemma.ID: CLIReferenceSnapshot],
		from oldID: Lemma.ID,
		to newID: Lemma.ID
	) throws {
		for (oldOwner, snapshot) in references {
			let owner = oldOwner.cliReplacingPrefix(oldID, with: newID)
			guard (try? declaredNode(owner)) != nil else {
				continue
			}
			try mutateDeclaredNode(owner) { node in
				node.type = Set(snapshot.type.map {
					$0.cliReplacingPrefix(oldID, with: newID)
				})
				if let oldTarget = snapshot.protonym {
					guard let parent = owner.parent else {
						throw ValidationError("A root lemma cannot be a synonym.")
					}
					let target = oldTarget.cliReplacingPrefix(oldID, with: newID)
					node.protonym = try target.relative(to: parent)
				}
				if let reference = snapshot.defaultReference {
					node.defaultValue = .reference(
						reference.cliReplacingPrefix(oldID, with: newID)
					)
				}
			}
		}
	}
}

private extension Lexicon.Graph.Node {

	func cliNode<Path>(path: Path) throws -> Self
	where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			return self
		}
		guard let child = children[name] else {
			throw ValidationError("Could not find lemma path component: \(name)")
		}
		return try child.cliNode(path: path.dropFirst())
	}

	mutating func cliMutate<Path>(
		path: Path,
		_ body: (inout Self) throws -> Void
	) throws where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw ValidationError("Could not find lemma path component: \(name)")
		}
		try child.cliMutate(path: path.dropFirst(), body)
		children[name] = child
	}
}

private extension Lemma.ID {
	func cliReplacingPrefix(_ oldID: Self, with newID: Self) -> Self {
		guard isInLineage(of: oldID) else {
			return self
		}
		return try! Self(
			components: newID.components + components.dropFirst(oldID.components.count)
		)
	}
}

extension Lexicon.Graph.Node.DefaultValue {
	static func parseAgentArgument(_ string: String) throws -> Self {
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("@") {
			let rawID = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
			return .reference(try Lemma.ID(parsing: rawID))
		}
		return .literal(.parse(trimmed))
	}
}
