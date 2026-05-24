//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon {

	struct ReferenceDiagnostic: Hashable, Sendable, CustomStringConvertible {
		public enum Kind: String, Hashable, Sendable {
			case externalType
			case externalProtonym
			case externalDefault
		}

		public var kind: Kind
		public var path: Lemma.ID
		public var reference: Lemma.ID

		public init(kind: Kind, path: Lemma.ID, reference: Lemma.ID) {
			self.kind = kind
			self.path = path
			self.reference = reference
		}

		public var description: String {
			"\(kind.rawValue) at \(path): \(reference)"
		}
	}

	struct BranchExport: Sendable {
		public var document: Document
		public var diagnostics: [ReferenceDiagnostic]

		public init(document: Document, diagnostics: [ReferenceDiagnostic]) {
			self.document = document
			self.diagnostics = diagnostics
		}
	}

	struct PasteResult: Sendable {
		public var lemma: Lemma?
		public var diagnostics: [ReferenceDiagnostic]

		public init(lemma: Lemma?, diagnostics: [ReferenceDiagnostic]) {
			self.lemma = lemma
			self.diagnostics = diagnostics
		}
	}
}

public extension Lemma {

	func exportBranchDocument() -> Lexicon.BranchExport {
		let root = regenerateNode()
			.rewritingInternalReferences(from: id, to: name, path: name, parentPath: nil)
		let diagnostics = root.referenceDiagnostics(branchID: root.name, path: root.name)
		let imports = diagnostics
			.map { Lexicon.Import($0.reference.components(separatedBy: ".").first ?? $0.reference) }
			.uniqued()
			.sorted { $0.reference < $1.reference }
		return .init(
			document: .init(
				date: lexicon.graph.date,
				roots: [root.name: root],
				imports: imports
			),
			diagnostics: diagnostics
		)
	}
}

#if EDITOR
public extension Lexicon {

	func paste(_ document: Document, root rootName: Graph.Node.Name? = nil, to lemma: Lemma) -> PasteResult {
		let graph: Graph
		do {
			graph = try document.graph(root: rootName)
		} catch {
			return .init(lemma: nil, diagnostics: [])
		}
		let diagnostics = graph.root.referenceDiagnostics(
			branchID: graph.root.name,
			path: graph.root.name
		)
		guard
			lemma.isValid(newChildName: graph.root.name),
			let path = lemma.graphPath
		else {
			return .init(lemma: nil, diagnostics: diagnostics)
		}

		var current = self.graph
		current.date = .init()
		current[path].children[graph.root.name] = graph.root.rewritingInternalReferences(
			from: graph.root.name,
			to: "\(lemma.id).\(graph.root.name)",
			path: "\(lemma.id).\(graph.root.name)",
			parentPath: lemma.id
		)
		reset(to: current)

		return .init(
			lemma: self["\(lemma.id).\(graph.root.name)"] ?? self.root,
			diagnostics: diagnostics
		)
	}
}
#endif

private extension Lexicon.Graph.Node {

	func rewritingInternalReferences(
		from oldRootID: Lemma.ID,
		to newRootID: Lemma.ID,
		path: Lemma.ID,
		parentPath: Lemma.ID?
	) -> Self {
		var node = self
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
				parentPath: path
			)
		}
		node.children = children
		return node
	}

	func referenceDiagnostics(branchID: Lemma.ID, path: Lemma.ID) -> [Lexicon.ReferenceDiagnostic] {
		var diagnostics: [Lexicon.ReferenceDiagnostic] = []

		for type in type.sorted() where type.isExternalReference(to: branchID) {
			diagnostics.append(.init(kind: .externalType, path: path, reference: type))
		}

		if let protonym = protonym, protonym.isExternalReference(to: branchID) {
			diagnostics.append(.init(kind: .externalProtonym, path: path, reference: protonym))
		}

		if case .reference(let reference) = defaultValue, reference.isExternalReference(to: branchID) {
			diagnostics.append(.init(kind: .externalDefault, path: path, reference: reference))
		}

		for (name, child) in children {
			diagnostics.append(contentsOf: child.referenceDiagnostics(branchID: branchID, path: "\(path).\(name)"))
		}

		return diagnostics
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

	func isExternalReference(to branchID: String) -> Bool {
		guard contains(".") else {
			return false
		}
		return self != branchID && !hasPrefix("\(branchID).")
	}
}

private extension Array where Element: Hashable {

	func uniqued() -> [Element] {
		var seen: Set<Element> = []
		return filter { seen.insert($0).inserted }
	}
}
