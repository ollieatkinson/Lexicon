import ArgumentParser
import Foundation
import Lexicon

struct Validate: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "validate",
		abstract: "Parse a lexicon and report name/reference diagnostics."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Flag(help: "Include non-fatal authoring warnings.")
	var strict = false

	@Flag(help: "Validate the source document without composing imports.")
	var sourceOnly = false

	func run() throws {
		let input = try input.validationInput(sourceOnly: sourceOnly)
		let output = ValidationOutput(
			input.document,
			strict: strict,
			additionalDiagnostics: input.diagnostics
		)
		try AgentJSON.print(output)
		guard output.valid else {
			throw ExitCode.failure
		}
	}
}

struct Lint: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "lint",
		abstract: "Run strict authoring checks and report errors and warnings."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Flag(help: "Lint the source document without composing imports.")
	var sourceOnly = false

	func run() throws {
		let input = try input.validationInput(sourceOnly: sourceOnly)
		let output = ValidationOutput(
			input.document,
			strict: true,
			additionalDiagnostics: input.diagnostics
		)
		try AgentJSON.print(output)
		guard output.valid else {
			throw ExitCode.failure
		}
	}
}

struct Inspect: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "inspect",
		abstract: "Inspect a document or lemma, including metadata and resolved children."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Optional lemma ID to inspect.")
	var id: String?

	@Flag(help: "Inspect the source document without composing imports.")
	var sourceOnly = false

	mutating func run() async throws {
		let document = try sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		if let id {
			let lemma = try await document.lemma(id)
			let inspection = await NodeInspection(lemma)
			try AgentJSON.print(inspection)
		} else {
			try AgentJSON.print(DocumentInspection(document))
		}
	}
}

struct Tree: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "tree",
		abstract: "Explore a lemma subtree, optionally using resolved inherited children."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Optional root lemma ID. Defaults to the sole document root.")
	var id: String?

	@Option(help: "Maximum child depth to include.")
	var depth = 3

	@Flag(help: "Use resolved inherited children instead of own graph children.")
	var inherited = false

	@Flag(help: "Include type, default, note, comment, and synonym metadata.")
	var metadata = false

	@Flag(help: "Explore the source document without composing imports.")
	var sourceOnly = false

	mutating func run() async throws {
		let document = try sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		let rootID = try id ?? document.firstRootID()
		if inherited {
			let lemma = try await document.lemma(rootID)
			let root = await TreeNode.resolved(lemma, depth: depth, metadata: metadata)
			try AgentJSON.print(TreeOutput(root: root))
		} else {
			try AgentJSON.print(TreeOutput(root: document.ownTree(id: rootID, depth: depth, metadata: metadata)))
		}
	}
}

struct Search: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "search",
		abstract: "Search lemma IDs, names, references, defaults, notes, and comments."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Search query terms.")
	var query: [String]

	@Option(help: "Maximum results to include. Use 0 for no limit.")
	var limit = 50

	@Option(help: "Restrict results to this root or subtree lemma ID.")
	var root: String?

	@Option(help: "Search mode: hybrid, token, lexical, semantic, or a comma-separated combination.")
	var mode = "hybrid"

	@Option(help: "Search scope: own, live, or full.")
	var scope = Lexicon.Search.Scope.own.rawValue

	@Option(help: "Minimum cosine similarity for semantic matches.")
	var semanticThreshold = 0.42

	@Option(help: "Semantic embedding provider: auto, system, mlx, onnx, or none.")
	var embeddingProvider = "auto"

	@Option(help: "Embedding model ID for MLX, or model path for ONNX semantic search.")
	var embeddingModel: String?

	@Option(help: "ONNX embedding model preset. Defaults to all-MiniLM-L6-v2.")
	var embeddingModelPreset: String?

	@Option(help: "ONNX embedding model manifest JSON path.")
	var embeddingModelManifest: URL?

	@Option(help: "Vocabulary path for ONNX semantic search.")
	var embeddingVocabulary: URL?

	@Option(help: "Model revision used in ONNX embedding cache identity.")
	var embeddingModelRevision: String?

	@Option(help: "Embedding cache path. Defaults to the user cache directory.")
	var embeddingCache: URL?

	@Flag(help: "Regenerate cached document embeddings before searching.")
	var rebuildEmbeddings = false

	@Flag(help: "Only search lemma IDs and names.")
	var namesOnly = false

	@Option(help: "Maximum resolved child depth to inspect when --scope live or --scope full.")
	var depth = Lexicon.Search.Bounds.defaultDepth

	@Option(help: "Maximum own-index candidates to expand when --scope live.")
	var candidates = Lexicon.Search.Bounds.defaultCandidates

	@Option(help: "Maximum resolved lemmas or child contexts to inspect when --scope live or --scope full.")
	var budget = Lexicon.Search.Bounds.defaultBudget

	@Flag(help: "Search the source document without composing imports.")
	var sourceOnly = false

	mutating func run() async throws {
		let query = query.joined(separator: " ")
		guard query.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty else {
			throw ValidationError("Search requires a query.")
		}
		let document = try sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		if let root {
			_ = try document.node(root)
		}
		let options = Lexicon.Search.Options(
			limit: limit,
			root: try root.map(Lemma.ID.init(parsing:)),
			mode: try Lexicon.Search.Mode(agentArgument: mode),
			scope: try Lexicon.Search.Scope(agentArgument: scope),
			includeReferences: !namesOnly,
			includeMetadata: !namesOnly,
			includeDefaults: !namesOnly,
			includeConnections: !namesOnly,
			semanticThreshold: semanticThreshold,
			bounds: .init(
				depth: depth,
				candidates: candidates,
				budget: budget
			)
		)
		let index = Lexicon.Search.Index(document: document, options: options)
		let results = try await index.search(
			query,
			in: document,
			input: input,
			embeddingProvider: try SearchEmbeddingProviderSelection(agentArgument: embeddingProvider),
			embeddingModel: embeddingModel,
			embeddingModelPreset: embeddingModelPreset,
			embeddingModelManifest: embeddingModelManifest,
			embeddingVocabulary: embeddingVocabulary,
			embeddingModelRevision: embeddingModelRevision,
			embeddingCache: embeddingCache,
			rebuildEmbeddings: rebuildEmbeddings
		)
		try AgentJSON.print(SearchOutput(query: query, results: results))
	}
}

struct Refs: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "refs",
		abstract: "Show outgoing and incoming type, synonym, and default references for a lemma."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to inspect references for.")
	var id: String

	@Flag(help: "Inspect references in the source document without composing imports.")
	var sourceOnly = false

	func run() throws {
		let document = try sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		try AgentJSON.print(RefsOutput(document: document, id: id))
	}
}

struct Excerpt: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "excerpt",
		abstract: "Export a branch as a lexicon fragment with reference diagnostics."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to export.")
	var id: String

	@Flag(help: "Export from the source document without composing imports.")
	var sourceOnly = false

	mutating func run() async throws {
		let document = try sourceOnly ? input.lexiconDocument() : input.composedLexiconDocument()
		let lemma = try await document.lemma(id)
		let export = await lemma.exportBranchDocument()
		try AgentJSON.print(ExcerptOutput(export))
	}
}

struct Format: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "format",
		abstract: "Emit or write canonical TaskPaper for a lexicon document."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Flag(help: "Only report whether the file is already canonical.")
	var check = false

	@Flag(help: "Rewrite the input file in place.")
	var write = false

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		let original = try String(contentsOf: input, encoding: .utf8)
		let document = try input.lexiconDocument()
		let formatted = TaskPaper.encode(document)
		if check {
			try AgentJSON.print(FormatOutput(changed: original != formatted, output: output?.path))
		} else if write {
			try Data(formatted.utf8).write(to: input, options: .atomic)
			try AgentJSON.print(WriteOutput(written: true, output: input.path))
		} else {
			try AgentWriter.write(formatted, output: output)
		}
	}
}

struct Diff: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "diff",
		abstract: "Compare two lexicon documents and report added, removed, and changed nodes."
	)

	@Argument(help: "Original TaskPaper lexicon path.")
	var before: URL

	@Argument(help: "Updated TaskPaper lexicon path.")
	var after: URL

	func run() throws {
		try AgentJSON.print(DiffOutput(
			before: try before.lexiconDocument(),
			after: try after.lexiconDocument()
		))
	}
}

struct Add: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "add",
		abstract: "Add a child node and print or write the updated document."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Parent lemma ID.")
	var parent: String

	@Argument(help: "New child name.")
	var name: String

	@Option(help: "Type reference. May be repeated.")
	var type: [String] = []

	@Option(help: "Optional protonym reference.")
	var protonym: String?

	@Option(name: .customLong("default"), help: "Optional literal JSON default or '@ lemma.id' reference.")
	var defaultValue: String?

	@Option(help: "Node note. May be repeated.")
	var note: [String] = []

	@Option(help: "Node comment. May be repeated.")
	var comment: [String] = []

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		_ = try Lemma.Name(validating: name)
		var document = try input.lexiconDocument()
		let node = try Lexicon.Graph.Node(
			type: Set(type.map(Lemma.ID.init(parsing:))),
			protonym: protonym.map(Lemma.RelativeID.init(parsing:)),
			defaultValue: defaultValue.map(Lexicon.Graph.Node.DefaultValue.parseAgentArgument),
			notes: note,
			comments: comment
		)
		try document.add(
			node,
			named: name,
			under: parent,
			sourceURL: input
		)
		try AgentWriter.write(document, output: output)
	}
}

struct Remove: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "remove",
		abstract: "Remove a root or child node and print or write the updated document."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to remove.")
	var id: String

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.remove(id, sourceURL: input)
		try AgentWriter.write(document, output: output)
	}
}

struct Rename: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "rename",
		abstract: "Rename a root or child node and rewrite affected references."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to rename.")
	var id: String

	@Argument(help: "New lemma name.")
	var name: String

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.rename(
			id,
			to: name,
			sourceURL: input
		)
		try AgentWriter.write(document, output: output)
	}
}

struct Move: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "move",
		abstract: "Move a node under a new parent and rewrite affected references."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to move.")
	var id: String

	@Argument(help: "Destination parent lemma ID.")
	var parent: String

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.move(
			id,
			under: parent,
			sourceURL: input
		)
		try AgentWriter.write(document, output: output)
	}
}

struct SetType: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-type",
		abstract: "Add a type reference to a node."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to modify.")
	var id: String

	@Argument(help: "Type reference to add.")
	var type: String

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		let type = try Lemma.ID(parsing: type)
		try document.updateNode(
			id,
			sourceURL: input
		) {
			$0.type.insert(type)
		}
		try AgentWriter.write(document, output: output)
	}
}

struct UnsetType: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "unset-type",
		abstract: "Remove a type reference from a node."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to modify.")
	var id: String

	@Argument(help: "Type reference to remove.")
	var type: String

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		let type = try Lemma.ID(parsing: type)
		try document.updateNode(id, sourceURL: input) { node in
			guard node.type.remove(type) != nil else {
				throw ValidationError("Node '\(id)' does not declare type '\(type)'.")
			}
		}
		try AgentWriter.write(document, output: output)
	}
}

struct SetProtonym: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-protonym",
		abstract: "Set or clear a synonym/protonym reference."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to modify.")
	var id: String

	@Argument(help: "Protonym reference. Omit when using --clear.")
	var protonym: String?

	@Flag(help: "Clear the protonym reference.")
	var clear = false

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		guard clear || protonym != nil else {
			throw ValidationError("Provide a protonym reference or --clear.")
		}
		guard !(clear && protonym != nil) else {
			throw ValidationError("Provide either a protonym reference or --clear, not both.")
		}
		var document = try input.lexiconDocument()
		let protonym = try protonym.map(Lemma.RelativeID.init(parsing:))
		try document.updateNode(id, sourceURL: input) { node in
			node.protonym = clear ? nil : protonym
		}
		try AgentWriter.write(document, output: output)
	}
}

struct SetDefault: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-default",
		abstract: "Set or clear a node default value."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to modify.")
	var id: String

	@Argument(help: "Literal JSON default or '@ lemma.id' reference. Omit when using --clear.")
	var value: String?

	@Flag(help: "Clear the default value.")
	var clear = false

	@Option(name: .shortAndLong, help: "Output path. If omitted, writes TaskPaper to stdout.")
	var output: URL?

	func run() throws {
		guard clear || value != nil else {
			throw ValidationError("Provide a default value or --clear.")
		}
		guard !(clear && value != nil) else {
			throw ValidationError("Provide either a default value or --clear, not both.")
		}
		var document = try input.lexiconDocument()
		let value = try value.map(Lexicon.Graph.Node.DefaultValue.parseAgentArgument)
		try document.updateNode(id, sourceURL: input) { node in
			node.defaultValue = clear ? nil : value
		}
		try AgentWriter.write(document, output: output)
	}
}

struct Note: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "note",
		abstract: "Add, remove, or clear node notes.",
		subcommands: [AddNote.self, RemoveNote.self, ClearNotes.self]
	)
}

struct AddNote: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "add")
	@Argument var input: URL
	@Argument var id: String
	@Argument var text: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.notes.append(text)
		}
		try AgentWriter.write(document, output: output)
	}
}

struct RemoveNote: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "remove")
	@Argument var input: URL
	@Argument var id: String
	@Argument var text: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.notes.removeAll { $0 == text }
		}
		try AgentWriter.write(document, output: output)
	}
}

struct ClearNotes: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "clear")
	@Argument var input: URL
	@Argument var id: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.notes.removeAll()
		}
		try AgentWriter.write(document, output: output)
	}
}

struct Comment: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "comment",
		abstract: "Add, remove, or clear node comments.",
		subcommands: [AddComment.self, RemoveComment.self, ClearComments.self]
	)
}

struct AddComment: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "add")
	@Argument var input: URL
	@Argument var id: String
	@Argument var text: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.comments.append(text)
		}
		try AgentWriter.write(document, output: output)
	}
}

struct RemoveComment: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "remove")
	@Argument var input: URL
	@Argument var id: String
	@Argument var text: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.comments.removeAll { $0 == text }
		}
		try AgentWriter.write(document, output: output)
	}
}

struct ClearComments: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "clear")
	@Argument var input: URL
	@Argument var id: String
	@Option(name: .shortAndLong) var output: URL?

	func run() throws {
		var document = try input.lexiconDocument()
		try document.updateNode(id, sourceURL: input) {
			$0.comments.removeAll()
		}
		try AgentWriter.write(document, output: output)
	}
}
