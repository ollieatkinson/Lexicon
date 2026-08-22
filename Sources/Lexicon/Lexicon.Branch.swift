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
		public var lemmaID: Lemma.ID
		public var diagnostics: [ReferenceDiagnostic]

		public init(lemmaID: Lemma.ID, diagnostics: [ReferenceDiagnostic]) {
			self.lemmaID = lemmaID
			self.diagnostics = diagnostics
		}
	}
}

public extension Lemma {

	func exportBranchDocument() -> Lexicon.BranchExport {
		let branchID = Lemma.ID(root: name)
		let root = node.rewritingInternalReferences(
			from: id,
			to: branchID,
			oldPath: id,
			newPath: branchID
		)
		let diagnostics = root.referenceDiagnostics(
			branchID: branchID,
			path: branchID
		)
		let imports = diagnostics
			.map { Lexicon.Import($0.reference.root.rawValue) }
			.uniqued()
			.sorted { $0.reference < $1.reference }
		return .init(
			document: .init(
				date: graph.date,
				roots: [name: root],
				imports: imports
			),
			diagnostics: diagnostics
		)
	}
}

#if EDITOR
public extension Lexicon {

	func paste(
		_ document: Document,
		root rootName: Lemma.Name,
		to lemma: Lemma
	) throws -> PasteResult {
		try requireCurrent(lemma)
		let graph = try document.graph(root: rootName)
		let branchID = Lemma.ID(root: rootName)
		let diagnostics = graph.root.referenceDiagnostics(
			branchID: branchID,
			path: branchID
		)
		let pasted = try insert(graph, under: lemma)
		return .init(lemmaID: pasted.id, diagnostics: diagnostics)
	}
}
#endif

private extension Lexicon.Graph.Node {

	func referenceDiagnostics(
		branchID: Lemma.ID,
		path: Lemma.ID
	) -> [Lexicon.ReferenceDiagnostic] {
		var diagnostics: [Lexicon.ReferenceDiagnostic] = []

		for type in type.sorted() where !type.isInLineage(of: branchID) {
			diagnostics.append(.init(
				kind: .externalType,
				path: path,
				reference: type
			))
		}

		if
			let protonym,
			let parent = path.parent
		{
			let target = parent.appending(protonym)
			if !target.isInLineage(of: branchID) {
				diagnostics.append(.init(
					kind: .externalProtonym,
					path: path,
					reference: target
				))
			}
		}

		if
			case .reference(let reference) = defaultValue,
			!reference.isInLineage(of: branchID)
		{
			diagnostics.append(.init(
				kind: .externalDefault,
				path: path,
				reference: reference
			))
		}

		for (name, child) in children {
			diagnostics.append(contentsOf: child.referenceDiagnostics(
				branchID: branchID,
				path: path.appending(name)
			))
		}

		return diagnostics
	}
}
