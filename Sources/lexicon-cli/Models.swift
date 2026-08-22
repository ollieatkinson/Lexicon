import Foundation
import Lexicon

struct ValidationOutput: Codable {
	var valid: Bool
	var diagnostics: [AgentDiagnostic]
	var roots: [String]

	init(
		_ document: Lexicon.Document,
		strict: Bool = false,
		additionalDiagnostics: [AgentDiagnostic] = []
	) {
		let documentDiagnostics = strict
			? document.lintDiagnostics
			: document.validationDiagnostics
		let diagnostics = Array(Set(additionalDiagnostics + documentDiagnostics)).sorted {
			($0.severity, $0.path, $0.kind, $0.reference ?? "", $0.message) <
				($1.severity, $1.path, $1.kind, $1.reference ?? "", $1.message)
		}
		self.valid = diagnostics.allSatisfy { $0.severity != "error" }
		self.diagnostics = diagnostics
		self.roots = document.roots.keys.map(\.description)
	}
}

struct AgentDiagnostic: Codable, Hashable {
	var severity: String
	var kind: String
	var path: String
	var reference: String?
	var message: String

	init(
		severity: String,
		kind: String,
		path: String,
		reference: String?,
		message: String
	) {
		self.severity = severity
		self.kind = kind
		self.path = path
		self.reference = reference
		self.message = message
	}

	init(_ diagnostic: Lexicon.Diagnostic) {
		self.init(
			severity: diagnostic.severity.rawValue,
			kind: diagnostic.code.rawValue,
			path: diagnostic.path?.description ?? "",
			reference: diagnostic.reference,
			message: diagnostic.message
		)
	}

	init(_ conflict: Lexicon.MergeConflict) {
		self.init(
			severity: "error",
			kind: conflict.kind.rawValue,
			path: conflict.path,
			reference: conflict.path,
			message: conflict.description
		)
	}
}

struct DocumentInspection: Codable {
	var date: Date
	var roots: [String]
	var imports: [Lexicon.Import]
	var notes: [String]
	var comments: [String]
	var diagnostics: [AgentDiagnostic]

	init(_ document: Lexicon.Document) {
		self.date = document.date
		self.roots = document.roots.keys.map(\.description)
		self.imports = document.imports
		self.notes = document.notes
		self.comments = document.comments
		self.diagnostics = document.validationDiagnostics
	}
}

struct TreeOutput: Codable {
	var root: TreeNode
}

struct SearchOutput: Codable {
	var query: String
	var count: Int
	var results: [Lexicon.Search.Result]

	init(query: String, results: [Lexicon.Search.Result]) {
		self.query = query
		self.count = results.count
		self.results = results
	}
}

struct TreeNode: Codable {
	var id: String
	var name: String
	var source: String?
	var isSynonym: Bool?
	var type: [String]?
	var ownType: [String]?
	var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
	var notes: [String]?
	var comments: [String]?
	var children: [TreeNode]

	static func own(id: Lemma.ID, node: Lexicon.Graph.Node, depth: Int, metadata: Bool) -> Self {
		let children: [TreeNode]
		if depth == 0 {
			children = []
		} else {
			children = node.children.map { name, child in
				TreeNode.own(
					id: id.appending(name),
					node: child,
					depth: depth - 1,
					metadata: metadata
				)
			}
		}
		return Self(
			id: id.description,
			name: id.name.description,
			source: nil,
			isSynonym: metadata ? node.protonym != nil : nil,
			type: metadata ? node.type.sorted().map(\.description) : nil,
			ownType: metadata ? node.type.sorted().map(\.description) : nil,
			defaultValue: metadata ? node.defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init) : nil,
			notes: metadata ? node.notes : nil,
			comments: metadata ? node.comments : nil,
			children: children
		)
	}

	@LexiconActor static func resolved(_ lemma: Lemma, depth: Int, metadata: Bool) -> Self {
		let children: [TreeNode]
		if depth == 0 {
			children = []
		} else {
			children = lemma.children.values.map {
				TreeNode.resolved($0, depth: depth - 1, metadata: metadata)
			}
		}
		return Self(
			id: lemma.id.description,
			name: lemma.name.description,
			source: metadata ? lemma.source.id.description : nil,
			isSynonym: metadata ? lemma.isSynonym : nil,
			type: metadata ? lemma.type.keys.map(\.description) : nil,
			ownType: metadata ? lemma.ownType.keys.map(\.description) : nil,
			defaultValue: metadata ? lemma.defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init) : nil,
			notes: metadata ? lemma.node.notes : nil,
			comments: metadata ? lemma.node.comments : nil,
			children: children
		)
	}
}

struct RefsOutput: Codable {
	var id: String
	var outgoing: [ReferenceUse]
	var incoming: [ReferenceUse]

	init(document: Lexicon.Document, id: String) throws {
		let id = try Lemma.ID(parsing: id)
		_ = try document.node(id.description)
		self.id = id.description
		let index = document.nodeIndex()
		let ids = Set(index.keys)
		self.outgoing = document.references(from: id, index: ids)
		self.incoming = index.keys.sorted().flatMap { source in
			document.references(from: source, index: ids).filter { use in
				use.resolved == id.description || use.reference == id.description
			}
		}
	}
}

struct ReferenceUse: Codable, Hashable {
	var kind: String
	var path: String
	var reference: String
	var resolved: String?
	var exists: Bool
}

struct NodeInspection: Codable {
	var id: String
	var name: String
	var source: String
	var isGraphNode: Bool
	var isSynonym: Bool
	var protonym: String?
	var type: [String]
	var ownType: [String]
	var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
	var notes: [String]
	var comments: [String]
	var ownChildren: [String]
	var resolvedChildren: [String]

	@LexiconActor init(_ lemma: Lemma) {
		self.id = lemma.id.description
		self.name = lemma.name.description
		self.source = lemma.source.id.description
		self.isGraphNode = lemma.isGraphNode
		self.isSynonym = lemma.isSynonym
		self.protonym = lemma.protonym?.id.description
		self.type = lemma.type.keys.map(\.description)
		self.ownType = lemma.ownType.keys.map(\.description)
		self.defaultValue = lemma.defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init)
		self.notes = lemma.node.notes
		self.comments = lemma.node.comments
		self.ownChildren = lemma.ownChildren.keys.map(\.description)
		self.resolvedChildren = lemma.children.keys.map(\.description)
	}
}

struct ExcerptOutput: Codable {
	var taskpaper: String
	var diagnostics: [ReferenceDiagnostic]

	init(_ export: Lexicon.BranchExport) {
		self.taskpaper = TaskPaper.encode(export.document)
		self.diagnostics = export.diagnostics.map(ReferenceDiagnostic.init)
	}
}

struct ReferenceDiagnostic: Codable {
	var kind: String
	var path: String
	var reference: String

	init(_ diagnostic: Lexicon.ReferenceDiagnostic) {
		self.kind = diagnostic.kind.rawValue
		self.path = diagnostic.path.description
		self.reference = diagnostic.reference.description
	}
}

struct FormatOutput: Codable {
	var changed: Bool
	var output: String?
}

struct DiffOutput: Codable {
	var added: [NodeSummary]
	var removed: [NodeSummary]
	var changed: [NodeChange]

	init(before: Lexicon.Document, after: Lexicon.Document) {
		let beforeIndex = before.nodeIndex()
		let afterIndex = after.nodeIndex()
		let beforeIDs = Set(beforeIndex.keys)
		let afterIDs = Set(afterIndex.keys)
		self.added = afterIDs.subtracting(beforeIDs)
			.sorted()
			.compactMap { id in afterIndex[id].map { NodeSummary(id: id, node: $0) } }
		self.removed = beforeIDs.subtracting(afterIDs)
			.sorted()
			.compactMap { id in beforeIndex[id].map { NodeSummary(id: id, node: $0) } }
		self.changed = beforeIDs.intersection(afterIDs)
			.sorted()
			.compactMap { id in
				guard let beforeNode = beforeIndex[id], let afterNode = afterIndex[id] else {
					return nil
				}
				let before = NodeSummary(id: id, node: beforeNode)
				let after = NodeSummary(id: id, node: afterNode)
				return before == after ? nil : NodeChange(
					id: id.description,
					before: before,
					after: after
				)
			}
	}
}

struct NodeChange: Codable {
	var id: String
	var before: NodeSummary
	var after: NodeSummary
}

struct NodeSummary: Codable, Equatable {
	var id: String
	var name: String
	var type: [String]
	var protonym: String?
	var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
	var notes: [String]
	var comments: [String]
	var ownChildren: [String]

	init(id: Lemma.ID, node: Lexicon.Graph.Node) {
		self.id = id.description
		self.name = id.name.description
		self.type = node.type.sorted().map(\.description)
		self.protonym = node.protonym?.description
		self.defaultValue = node.defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init)
		self.notes = node.notes
		self.comments = node.comments
		self.ownChildren = node.children.keys.map(\.description)
	}
}

struct WriteOutput: Codable {
	var written: Bool
	var output: String
}

struct TaskPaperOutput: Codable {
	var taskpaper: String
}

struct InteractiveMessage: Codable {
	var ok = true
	var event: String
	var message: String
}

struct InteractiveError: Codable {
	var ok = false
	var message: String
}

struct InteractiveHelp: Codable {
	var commands = [
		"validate [--strict]",
		"lint",
		"inspect [id]",
		"ls [id] [--metadata]",
		"tree [id] [--depth n] [--inherited] [--metadata]",
		"search query [--mode hybrid|token|lexical|semantic] [--scope own|live|full] [--depth n] [--budget n] [--limit n] [--root id]",
		"refs id",
		"excerpt id",
		"add parent name",
		"remove id",
		"rename id name",
		"move id parent",
		"set-type id type",
		"unset-type id type",
		"set-protonym id reference|--clear",
		"set-default id value|--clear",
		"note add|remove|clear id [text]",
		"comment add|remove|clear id [text]",
		"format",
		"save [path]",
		"quit",
	]
}
