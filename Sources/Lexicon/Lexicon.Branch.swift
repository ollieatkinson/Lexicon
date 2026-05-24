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
		public var lemmaID: Lemma.ID?
		public var diagnostics: [ReferenceDiagnostic]

		public init(lemmaID: Lemma.ID?, diagnostics: [ReferenceDiagnostic]) {
			self.lemmaID = lemmaID
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
			return .init(lemmaID: nil, diagnostics: [])
		}
		let diagnostics = graph.root.referenceDiagnostics(
			branchID: graph.root.name,
			path: graph.root.name
		)
		guard
			lemma.isValid(newChildName: graph.root.name),
			let path = lemma.graphPath
		else {
			return .init(lemmaID: nil, diagnostics: diagnostics)
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
			lemmaID: "\(lemma.id).\(graph.root.name)",
			diagnostics: diagnostics
		)
	}
}
#endif

private extension Lexicon.Graph.Node {

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

	func isExternalReference(to branchID: String) -> Bool {
		guard contains(".") else {
			return false
		}
		return self != branchID && !hasPrefix("\(branchID).")
	}
}
