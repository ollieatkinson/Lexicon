//
// github.com/screensailor 2026
//

import Foundation

#if EDITOR
public extension Lexicon.Document {

	struct Editor {
		public private(set) var document: Lexicon.Document

		public init(_ document: Lexicon.Document) throws {
			self.document = try document.validated()
		}

		public func node(_ id: Lemma.ID) throws -> Lexicon.Graph.Node {
			try document.node(id)
		}

		@discardableResult
		public mutating func addChild(
			named name: Lemma.Name,
			to parentID: Lemma.ID,
			node: Lexicon.Graph.Node = .init()
		) throws -> Lemma.ID {
			let newID = parentID.appending(name)
			try transaction { document in
				try document.updateNode(parentID) { parent in
					guard parent.protonym == nil else {
						throw LexiconError("Cannot add a child to synonym '\(parentID)'")
					}
					guard parent.children[name] == nil else {
						throw LexiconError("Lemma '\(newID)' already exists")
					}
					parent.children[name] = node
				}
			}
			return newID
		}

		@discardableResult
		public mutating func insert(
			_ graph: Lexicon.Graph,
			under parentID: Lemma.ID
			) throws -> Lemma.ID {
				let newID = parentID.appending(graph.rootName)
				let oldID = Lemma.ID(root: graph.rootName)
				var root = graph.root.rewritingInternalReferences(
					from: Lemma.ID(root: graph.rootName),
					to: newID,
					oldPath: oldID,
					newPath: newID
				)
				if
					let protonym = root.protonym,
					Lexicon.Generation(
						lexiconID: .init(),
						revision: .initial,
						document: document
					).resolve(parentID.appending(protonym)) == nil
				{
					root.protonym = nil
				}
				try transaction { document in
				try document.updateNode(parentID) { parent in
					guard parent.protonym == nil else {
						throw LexiconError("Cannot insert below synonym '\(parentID)'")
					}
					guard parent.children[graph.rootName] == nil else {
						throw LexiconError("Lemma '\(newID)' already exists")
					}
					parent.children[graph.rootName] = root
				}
			}
			return newID
		}

		@discardableResult
		public mutating func rename(
			_ id: Lemma.ID,
			to newName: Lemma.Name
		) throws -> Lemma.ID {
			let newID: Lemma.ID
			if let parent = id.parent {
				newID = parent.appending(newName)
			} else {
				newID = Lemma.ID(root: newName)
			}
			guard newID != id else {
				throw LexiconError("Lemma '\(id)' already has name '\(newName)'")
			}

			try transaction { document in
				let references = try document.referenceSnapshot()
				if let parentID = id.parent {
					try document.updateNode(parentID) { parent in
						guard parent.children[newName] == nil else {
							throw LexiconError("Lemma '\(newID)' already exists")
						}
						guard let node = parent.children.removeValue(forKey: id.name) else {
							throw LexiconError("Could not find lemma '\(id)'")
						}
						parent.children[newName] = node
					}
				} else {
					guard document.roots[newName] == nil else {
						throw LexiconError("Root '\(newName)' already exists")
					}
					guard let root = document.roots.removeValue(forKey: id.root) else {
						throw LexiconError("Could not find root '\(id)'")
					}
					document.roots[newName] = root
				}
				try document.rewriteReferences(
					references,
					from: id,
					to: newID
				)
			}
			return newID
		}

		@discardableResult
		public mutating func move(
			_ id: Lemma.ID,
			under parentID: Lemma.ID
		) throws -> Lemma.ID {
			guard !parentID.isInLineage(of: id) else {
				throw LexiconError("Cannot move '\(id)' under its own descendant '\(parentID)'")
			}
			let newID = parentID.appending(id.name)
			try transaction { document in
				let references = try document.referenceSnapshot()
				let node = try document.take(id)
				try document.updateNode(parentID) { parent in
					guard parent.protonym == nil else {
						throw LexiconError("Cannot move below synonym '\(parentID)'")
					}
					guard parent.children[id.name] == nil else {
						throw LexiconError("Lemma '\(newID)' already exists")
					}
					parent.children[id.name] = node
				}
				try document.rewriteReferences(
					references,
					from: id,
					to: newID
				)
			}
			return newID
		}

		public mutating func delete(_ id: Lemma.ID) throws {
			try transaction { document in
				guard document.roots.count > 1 || id.parent != nil else {
					throw LexiconError("Cannot delete the document's last root")
				}
					let references = try document.referenceSnapshot()
					for (owner, snapshot) in references where !owner.isInLineage(of: id) {
						let referenced = snapshot.type.contains(where: { $0.isInLineage(of: id) }) ||
							snapshot.protonym?.sourceID.isInLineage(of: id) == true ||
							snapshot.defaultReference?.sourceID.isInLineage(of: id) == true
					if referenced {
						throw LexiconError(
							"Cannot delete '\(id)' because '\(owner)' references its subtree"
						)
					}
				}
				_ = try document.take(id)
			}
		}

		public mutating func addType(
			_ type: Lemma.ID,
			to id: Lemma.ID
		) throws {
			try transaction { document in
				guard let target = try? document.node(type), target.protonym == nil else {
					throw LexiconError("Type target '\(type)' must be a declared non-synonym lemma")
				}
				try document.updateNode(id) { node in
					guard node.protonym == nil else {
						throw LexiconError("A synonym cannot declare type references")
					}
					guard node.type.insert(type).inserted else {
						throw LexiconError("Lemma '\(id)' already declares type '\(type)'")
					}
				}
			}
		}

		public mutating func removeType(
			_ type: Lemma.ID,
			from id: Lemma.ID
		) throws {
			try transaction { document in
					try document.updateNode(id) { node in
						guard node.type.remove(type) != nil else {
							throw LexiconError("Lemma '\(id)' does not declare type '\(type)'")
						}
					}
					try document.removeUnresolvedSynonyms()
				}
			}

		public mutating func setProtonym(
			_ targetID: Lemma.ID,
			of id: Lemma.ID
		) throws {
			guard let parentID = id.parent else {
				throw LexiconError("A root lemma cannot be a synonym")
			}
				let relative = try targetID.relative(to: parentID)
				try transaction { document in
					let generation = Lexicon.Generation(
						lexiconID: .init(),
						revision: .initial,
						document: document
					)
					guard generation.resolve(targetID) != nil else {
						throw LexiconError("Could not resolve protonym target '\(targetID)'")
					}
					try document.updateNode(id) { node in
					node.children.removeAll()
					node.type.removeAll()
					node.protonym = relative
				}
			}
		}

		public mutating func clearProtonym(of id: Lemma.ID) throws {
			try transaction { document in
				try document.updateNode(id) { node in
					guard node.protonym != nil else {
						throw LexiconError("Lemma '\(id)' is not a synonym")
					}
					node.protonym = nil
				}
			}
		}
	}
}

private extension Lexicon.Document.Editor {

	mutating func transaction(
		_ body: (inout Lexicon.Document) throws -> Void
	) throws {
		var candidate = document
		try body(&candidate)
		candidate.date = Date()
		document = try candidate.validated()
	}

}

private extension Lexicon.Document {

	struct ReferenceSnapshot {
		var type: Set<Lemma.ID>
		var protonym: ResolvedReference?
		var defaultReference: ResolvedReference?
	}

	struct ResolvedReference {
		var requestedID: Lemma.ID
		var sourceID: Lemma.ID
		var resolvedPrefixes: [Lemma.ID?]

		func rewriting(
			from oldID: Lemma.ID,
			to newID: Lemma.ID
		) -> Lemma.ID {
			guard sourceID.isInLineage(of: oldID) else {
				return requestedID
			}
			if requestedID.isInLineage(of: oldID) {
				return requestedID.replacingPrefix(oldID, with: newID)
			}
			if oldID.parent == newID.parent {
				if let index = resolvedPrefixes.firstIndex(where: { $0 == oldID }) {
					var components = requestedID.components
					components[index] = newID.name
					return try! Lemma.ID(components: components)
				}
				return requestedID
			}
			return sourceID.replacingPrefix(oldID, with: newID)
		}
	}

	func node(_ id: Lemma.ID) throws -> Lexicon.Graph.Node {
		guard let root = roots[id.root] else {
			throw LexiconError("Could not find root '\(id.root)'")
		}
		return try root.node(path: id.components.dropFirst())
	}

	mutating func updateNode(
		_ id: Lemma.ID,
		_ body: (inout Lexicon.Graph.Node) throws -> Void
	) throws {
		guard var root = roots[id.root] else {
			throw LexiconError("Could not find root '\(id.root)'")
		}
		try root.mutate(path: id.components.dropFirst(), body)
		roots[id.root] = root
	}

	mutating func take(_ id: Lemma.ID) throws -> Lexicon.Graph.Node {
		if id.parent == nil {
			guard let root = roots.removeValue(forKey: id.root) else {
				throw LexiconError("Could not find root '\(id)'")
			}
			return root
		}
		guard let parentID = id.parent else {
			throw LexiconError("Could not find parent of '\(id)'")
		}
		var removed: Lexicon.Graph.Node?
		try updateNode(parentID) { parent in
			removed = parent.children.removeValue(forKey: id.name)
		}
		guard let removed else {
			throw LexiconError("Could not find lemma '\(id)'")
		}
		return removed
	}

	func referenceSnapshot() throws -> [Lemma.ID: ReferenceSnapshot] {
		let generation = Lexicon.Generation(
			lexiconID: .init(),
			revision: .initial,
			document: self
		)
		var result: [Lemma.ID: ReferenceSnapshot] = [:]
		for id in generation.rawNodes.keys {
			guard let node = generation.rawNodes[id] else {
				continue
			}
			let protonym: ResolvedReference?
			if let reference = node.protonym, let parent = id.parent {
				protonym = resolvedReference(
					parent.appending(reference),
					generation: generation
				)
			} else {
				protonym = nil
			}
			let defaultReference: ResolvedReference?
			if case .reference(let reference) = node.defaultValue {
				defaultReference = resolvedReference(reference, generation: generation)
			} else {
				defaultReference = nil
			}
			result[id] = ReferenceSnapshot(
				type: node.type,
				protonym: protonym,
				defaultReference: defaultReference
			)
		}
		return result
	}

	mutating func rewriteReferences(
		_ references: [Lemma.ID: ReferenceSnapshot],
		from oldID: Lemma.ID,
		to newID: Lemma.ID
	) throws {
		for oldOwnerID in references.keys.sorted() {
			guard let snapshot = references[oldOwnerID] else {
				continue
			}
			let ownerID = oldOwnerID.replacingPrefix(oldID, with: newID)
			guard (try? node(ownerID)) != nil else {
				continue
			}
			try updateNode(ownerID) { node in
				node.type = Set(snapshot.type.map {
					$0.replacingPrefix(oldID, with: newID)
				})
				if let reference = snapshot.protonym {
					guard let parent = ownerID.parent else {
						throw LexiconError("A root lemma cannot be a synonym")
					}
					let target = reference.rewriting(from: oldID, to: newID)
					node.protonym = try target.relative(to: parent)
				}
				if let reference = snapshot.defaultReference {
					node.defaultValue = .reference(
						reference.rewriting(from: oldID, to: newID)
					)
				}
			}
		}
	}

	func resolvedReference(
		_ requestedID: Lemma.ID,
		generation: Lexicon.Generation
	) -> ResolvedReference? {
		guard let resolution = generation.resolve(requestedID) else {
			return nil
		}
		let prefixes = requestedID.components.indices.map { index -> Lemma.ID? in
			guard
				let prefix = try? Lemma.ID(
					components: Array(requestedID.components[...index])
				)
			else {
				return nil
			}
			return generation.resolve(prefix)?.nodeID
		}
		return ResolvedReference(
			requestedID: requestedID,
			sourceID: resolution.nodeID,
			resolvedPrefixes: prefixes
		)
	}

	mutating func removeUnresolvedSynonyms() throws {
		while true {
			let generation = Lexicon.Generation(
				lexiconID: .init(),
				revision: .initial,
				document: self
			)
			let invalid = generation.rawNodes.keys.filter { id in
				guard
					let node = generation.rawNodes[id],
					let protonym = node.protonym,
					let parent = id.parent
				else {
					return false
				}
				return generation.resolve(parent.appending(protonym)) == nil
			}.sorted {
				($0.components.count, $0) > ($1.components.count, $1)
			}
			guard invalid.isNotEmpty else {
				return
			}
			for id in invalid {
				_ = try take(id)
			}
		}
	}
}

private extension Lexicon.Graph.Node {

	func node<Path>(path: Path) throws -> Self
	where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			return self
		}
		guard let child = children[name] else {
			throw LexiconError("Could not find lemma path component '\(name)'")
		}
		return try child.node(path: path.dropFirst())
	}

	mutating func mutate<Path>(
		path: Path,
		_ body: (inout Self) throws -> Void
	) throws where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw LexiconError("Could not find lemma path component '\(name)'")
		}
		try child.mutate(path: path.dropFirst(), body)
		children[name] = child
	}
}

private extension Lemma.ID {

	func replacingPrefix(_ oldID: Self, with newID: Self) -> Self {
		guard isInLineage(of: oldID) else {
			return self
		}
		let suffix = components.dropFirst(oldID.components.count)
		return try! Self(components: newID.components + suffix)
	}
}
#endif
