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

	func run() throws {
		let document = try input.lexiconDocument()
		try AgentJSON.print(ValidationOutput(document, strict: strict))
	}
}

struct Lint: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "lint",
		abstract: "Run strict authoring checks and report errors and warnings."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	func run() throws {
		let document = try input.lexiconDocument()
		try AgentJSON.print(ValidationOutput(document, strict: true))
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

	mutating func run() async throws {
		let document = try input.composedLexiconDocument()
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

	@Argument(help: "Optional root lemma ID. Defaults to the first document root.")
	var id: String?

	@Option(help: "Maximum child depth to include.")
	var depth = 3

	@Flag(help: "Use resolved inherited children instead of own graph children.")
	var inherited = false

	@Flag(help: "Include type, default, note, comment, and synonym metadata.")
	var metadata = false

	mutating func run() async throws {
		let document = try input.composedLexiconDocument()
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

struct Refs: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "refs",
		abstract: "Show outgoing and incoming type, synonym, and default references for a lemma."
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Argument(help: "Lemma ID to inspect references for.")
	var id: String

	func run() throws {
		let document = try input.composedLexiconDocument()
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

	mutating func run() async throws {
		let document = try input.composedLexiconDocument()
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
			try Data(formatted.utf8).write(to: input)
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
		guard Lemma.isValid(name: name) else {
			throw ValidationError("Invalid lemma name: \(name)")
		}
		var document = try input.lexiconDocument()
		var node = Lexicon.Graph.Node(
			name: name,
			children: [:],
			type: Set(type),
			defaultValue: defaultValue.map(Lexicon.Graph.Node.DefaultValue.parseAgentArgument),
			notes: note,
			comments: comment
		)
		node.protonym = protonym
		try document.add(node, under: parent)
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
		try document.remove(id)
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
		try document.rename(id, to: name)
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
		try document.move(id, under: parent)
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
		try document.updateNode(id) { $0.type.insert(type) }
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
		try document.updateNode(id) { node in
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
		var document = try input.lexiconDocument()
		try document.updateNode(id) { node in
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
		var document = try input.lexiconDocument()
		try document.updateNode(id) { node in
			node.defaultValue = clear ? nil : value.map(Lexicon.Graph.Node.DefaultValue.parseAgentArgument)
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
		try document.updateNode(id) { $0.notes.append(text) }
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
		try document.updateNode(id) { $0.notes.removeAll { $0 == text } }
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
		try document.updateNode(id) { $0.notes.removeAll() }
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
		try document.updateNode(id) { $0.comments.append(text) }
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
		try document.updateNode(id) { $0.comments.removeAll { $0 == text } }
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
		try document.updateNode(id) { $0.comments.removeAll() }
		try AgentWriter.write(document, output: output)
	}
}

