//
// github.com/screensailor 2026
//

import Foundation
import _Collections

public protocol LexiconImportResolving {
	func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document?
}

public struct EmptyLexiconImportResolver: LexiconImportResolving {
	public init() {}
	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		nil
	}
}

public struct DictionaryLexiconImportResolver: LexiconImportResolving {
	public var documents: [String: Lexicon.Document]

	public init(_ documents: [String: Lexicon.Document]) {
		self.documents = documents
	}

	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		documents[`import`.reference]
	}
}

public struct FileLexiconImportResolver: LexiconImportResolving {
	public var baseURL: URL
	public var allowRemote: Bool

	public init(baseURL: URL, allowRemote: Bool = false) {
		self.baseURL = baseURL
		self.allowRemote = allowRemote
	}

	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		let url: URL
		switch `import`.location {
			case .local:
				guard let local = localURL(for: `import`.reference) else {
					return nil
				}
				url = local
			case .remote:
				guard
					allowRemote,
					let remote = URL(string: `import`.reference),
					let scheme = remote.scheme?.lowercased(),
					["http", "https"].contains(scheme)
				else {
					return nil
				}
				url = remote
		}
		return try TaskPaper(Data(contentsOf: url)).decodeDocument()
	}

	private func localURL(for reference: String) -> URL? {
		let base = baseURL.standardizedFileURL.resolvingSymlinksInPath()
		let candidate = URL(fileURLWithPath: reference, relativeTo: base)
			.standardizedFileURL
			.resolvingSymlinksInPath()
		guard candidate.isFileURL else {
			return nil
		}
		guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else {
			return nil
		}
		return candidate
	}
}

public extension Lexicon {

	struct MergeConflict: Hashable, CustomStringConvertible {
		public enum Kind: String, Hashable {
			case protonym
			case defaultValue
			case nodeKind
			case importResolution
		}

		public var kind: Kind
		public var path: Lemma.ID
		public var existing: String
		public var incoming: String

		public init(kind: Kind, path: Lemma.ID, existing: String, incoming: String) {
			self.kind = kind
			self.path = path
			self.existing = existing
			self.incoming = incoming
		}

		public var description: String {
			"\(kind.rawValue) conflict at \(path): \(existing) <> \(incoming)"
		}
	}

	struct MergePlan {
		public var document: Document
		public var conflicts: [MergeConflict]

		public var hasConflicts: Bool {
			conflicts.isNotEmpty
		}
	}
}

public extension Lexicon.Document {

	static func merge(_ documents: [Self]) -> Lexicon.MergePlan {
		guard let rootName = documents.compactMap(\.canonicalRootName).first else {
			return .init(document: .init(), conflicts: [])
		}
		return Lexicon.MergePlan(
			document: Lexicon.CRDT.Replica(
				documents: documents.map { $0.normalizedForMerge(root: rootName) }
			).materialized().normalizedForMerge(root: rootName),
			conflicts: []
		)
	}

	func merging(_ other: Self) -> Lexicon.MergePlan {
		Self.merge([self, other])
	}

	func composed(resolving resolver: LexiconImportResolving = EmptyLexiconImportResolver()) throws -> Lexicon.MergePlan {
		try composed(resolving: resolver, visited: [])
	}
}

private extension Lexicon.Document {

	func composed(resolving resolver: LexiconImportResolving, visited: Set<String>) throws -> Lexicon.MergePlan {
		guard let rootName = canonicalRootName else {
			return .init(document: self, conflicts: [])
		}
		var documents: [Lexicon.Document] = []
		var conflicts: [Lexicon.MergeConflict] = []
		var local = normalizedForMerge(root: rootName)

		for `import` in local.imports.sorted(by: { $0.reference < $1.reference }) {
			guard !visited.contains(`import`.reference) else {
				continue
			}
			guard let document = try resolver.resolve(`import`) else {
				conflicts.append(.init(
					kind: .importResolution,
					path: `import`.reference,
					existing: "unresolved",
					incoming: `import`.location.rawValue
				))
				continue
			}
			let imported = try document.composed(
				resolving: resolver,
				visited: visited.union([`import`.reference])
			)
			documents.append(try imported.document.grafted(onto: rootName, in: rootName))
			conflicts.append(contentsOf: imported.conflicts)
			local.imports.removeAll { $0 == `import` }
		}

		for connection in local.connections.sorted(by: {
			($0.path, $0.import.reference) < ($1.path, $1.import.reference)
		}) {
			guard !visited.contains(connection.import.reference) else {
				continue
			}
			guard let document = try resolver.resolve(connection.import) else {
				conflicts.append(.init(
					kind: .importResolution,
					path: connection.path,
					existing: "unresolved",
					incoming: connection.import.location.rawValue
				))
				continue
			}
			let imported = try document.composed(
				resolving: resolver,
				visited: visited.union([connection.import.reference])
			)
			documents.append(try imported.document.grafted(onto: connection.path, in: rootName))
			conflicts.append(contentsOf: imported.conflicts)
			try local.removeConnection(connection.import, at: connection.path)
		}
		documents.append(local)

		let plan = Lexicon.Document.merge(documents)
		conflicts = conflicts.sorted {
			($0.path, $0.kind.rawValue, $0.existing, $0.incoming) <
			($1.path, $1.kind.rawValue, $1.existing, $1.incoming)
		}

		return .init(document: plan.document, conflicts: conflicts.uniqued())
	}
}

private extension Lexicon.Document {

	var canonicalRootName: String? {
		roots.keys.first
	}

	var connections: [(path: String, import: Lexicon.Import)] {
		roots.values.flatMap { root in
			var connections: [(path: String, import: Lexicon.Import)] = []
			root.traverse(sorted: true) { id, _, node in
				for `import` in node.connections.sorted(by: { $0.reference < $1.reference }) {
					connections.append((id, `import`))
				}
			}
			return connections
		}
	}

	func normalizedForMerge(root rootName: String) -> Self {
		var document = self
		var root = roots[rootName] ?? .init(name: rootName)
		root.name = rootName

		for (name, node) in roots where name != rootName {
			let path = "\(rootName).\(name)"
			root.children[name] = node.rebased(
				from: name,
				to: path,
				path: path,
				parentPath: rootName,
				name: name
			)
		}

		document.roots = [rootName: root]
		return document
	}

	func grafted(onto anchorID: String, in rootName: String) throws -> Self {
		guard let sourceRootName = canonicalRootName, let sourceRoot = roots[sourceRootName] else {
			return .init(roots: [rootName: .init(name: rootName)])
		}
		let components = anchorID.components(separatedBy: ".").filter { !$0.isEmpty }
		guard components.first == rootName, let anchorName = components.last else {
			throw "Cannot graft imported lexicon at '\(anchorID)' inside root '\(rootName)'"
		}
		let parentPath = components.dropLast().unlessEmpty?.joined(separator: ".")
		let leaf = sourceRoot.rebased(
			from: sourceRootName,
			to: anchorID,
			path: anchorID,
			parentPath: parentPath,
			name: anchorName
		)
		return .init(
			date: date,
			roots: [rootName: Self.scaffold(components: Array(components), leaf: leaf)],
			notes: notes,
			comments: comments
		)
	}

	static func scaffold(components: [String], leaf: Lexicon.Graph.Node) -> Lexicon.Graph.Node {
		guard components.count > 1 else {
			return leaf
		}
		var node = leaf
		for index in stride(from: components.count - 2, through: 0, by: -1) {
			node = .init(
				name: components[index],
				children: [node.name: node]
			)
		}
		return node
	}

	mutating func removeConnection(_ import: Lexicon.Import, at path: String) throws {
		let components = path.components(separatedBy: ".").filter { !$0.isEmpty }
		guard let rootName = components.first, roots[rootName] != nil else {
			return
		}
		try roots.mutate(rootName) { root in
			try root.mutate(path: components.dropFirst()) { node in
				node.connections.removeAll { $0 == `import` }
			}
		}
	}
}

private extension Lexicon.Graph.Node {

	func rebased(
		from oldRootID: String,
		to newRootID: String,
		path: String,
		parentPath: String?,
		name newName: String
	) -> Self {
		var node = self
		node.name = newName
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
			children[name] = child.rebased(
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

	mutating func mutate<Path>(path: Path, body: (inout Self) throws -> Void) throws where Path: Collection, Path.Element == String {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw "Could not find lemma path component: \(name)"
		}
		try child.mutate(path: path.dropFirst(), body: body)
		children[name] = child
	}
}

private extension SortedDictionary where Key == String, Value == Lexicon.Graph.Node {

	mutating func mutate(_ key: Key, body: (inout Value) throws -> Void) throws {
		guard var value = self[key] else {
			throw "Could not find lemma: \(key)"
		}
		try body(&value)
		self[key] = value
	}
}

private extension String {

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

private extension Array where Element: Hashable {

	func uniqued() -> [Element] {
		var seen: Set<Element> = []
		return filter { seen.insert($0).inserted }
	}
}

extension Lexicon.Graph.Node.DefaultValue: CustomStringConvertible {

	public var description: String {
		switch self {
			case .literal(let value):
				return value.description
			case .reference(let id):
				return "@ \(id)"
		}
	}
}

extension JSONValue: CustomStringConvertible {

	public var description: String {
		switch self {
			case .string(let value):
				return value
			case .number(let value):
				return "\(value)"
			case .bool(let value):
				return "\(value)"
			case .array(let value):
				return "[" + value.map(\.description).joined(separator: ", ") + "]"
			case .object(let value):
				return "{" + value.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}"
			case .null:
				return "null"
		}
	}
}
