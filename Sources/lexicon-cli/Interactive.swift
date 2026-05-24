import ArgumentParser
import Foundation
import Lexicon

struct Interactive: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "interactive",
		abstract: "Start a line-oriented session for exploring and editing one lexicon document.",
		aliases: ["repl"]
	)

	@Argument(help: "TaskPaper lexicon path.")
	var input: URL

	@Option(name: .shortAndLong, help: "Default save path. Defaults to the input path.")
	var output: URL?

	@Flag(help: "Emit machine-readable JSON lines.")
	var json = false

	mutating func run() async throws {
		var session = InteractiveSession(
			document: try input.lexiconDocument(),
			input: input,
			output: output ?? input,
			format: json ? .json : .text
		)
		try session.emit(InteractiveMessage(event: "ready", message: "lexicon interactive ready"))
		while let line = readLine() {
			let shouldContinue = await session.handle(line)
			if !shouldContinue {
				break
			}
		}
	}
}

enum InteractiveFormat {
	case text
	case json
}

struct InteractiveSession {
	var document: Lexicon.Document
	var input: URL
	var output: URL
	var format: InteractiveFormat

	mutating func handle(_ line: String) async -> Bool {
		do {
			let arguments = try line.shellWords()
			guard let command = arguments.first else {
				return true
			}
			let rest = Array(arguments.dropFirst())
			switch command {
				case "quit", "exit":
					try emit(InteractiveMessage(event: "bye", message: "session closed"))
					return false
				case "help":
					try emit(InteractiveHelp())
				case "validate":
					try emit(ValidationOutput(document, strict: rest.contains("--strict")))
				case "lint":
					try emit(ValidationOutput(document, strict: true))
				case "inspect":
					let resolved = try composedDocument()
					if let id = rest.first {
						let lemma = try await resolved.lemma(id)
						let inspection = await NodeInspection(lemma)
						try emit(inspection)
					} else {
						try emit(DocumentInspection(resolved))
					}
				case "ls":
					let arguments = rest.contains("--depth") ? rest : ["--depth", "1"] + rest
					try await handleTree(arguments)
				case "tree":
					try await handleTree(rest)
				case "refs":
					let id = try rest.required(0, named: "id")
					try emit(RefsOutput(document: try composedDocument(), id: id))
				case "excerpt":
					let id = try rest.required(0, named: "id")
					let lemma = try await composedDocument().lemma(id)
					let export = await lemma.exportBranchDocument()
					try emit(ExcerptOutput(export))
				case "add":
					let parent = try rest.required(0, named: "parent")
					let name = try rest.required(1, named: "name")
					try document.add(.init(name: name), under: parent)
					try emit(InteractiveMessage(event: "changed", message: "added \(parent).\(name)"))
				case "remove":
					let id = try rest.required(0, named: "id")
					try document.remove(id)
					try emit(InteractiveMessage(event: "changed", message: "removed \(id)"))
				case "rename":
					let id = try rest.required(0, named: "id")
					let name = try rest.required(1, named: "name")
					try document.rename(id, to: name)
					try emit(InteractiveMessage(event: "changed", message: "renamed \(id)"))
				case "move":
					let id = try rest.required(0, named: "id")
					let parent = try rest.required(1, named: "parent")
					try document.move(id, under: parent)
					try emit(InteractiveMessage(event: "changed", message: "moved \(id)"))
				case "set-type":
					let id = try rest.required(0, named: "id")
					let type = try rest.required(1, named: "type")
					try document.updateNode(id) { $0.type.insert(type) }
					try emit(InteractiveMessage(event: "changed", message: "set type \(type) on \(id)"))
				case "unset-type":
					let id = try rest.required(0, named: "id")
					let type = try rest.required(1, named: "type")
					try document.updateNode(id) { node in
						_ = node.type.remove(type)
					}
					try emit(InteractiveMessage(event: "changed", message: "removed type \(type) from \(id)"))
				case "set-protonym":
					let id = try rest.required(0, named: "id")
					let protonym = rest.dropFirst().first
					try document.updateNode(id) { $0.protonym = protonym == "--clear" ? nil : protonym }
					try emit(InteractiveMessage(event: "changed", message: "updated protonym on \(id)"))
				case "set-default":
					let id = try rest.required(0, named: "id")
					let value = rest.dropFirst().joined(separator: " ")
					try document.updateNode(id) { node in
						node.defaultValue = value == "--clear" ? nil : .parseAgentArgument(value)
					}
					try emit(InteractiveMessage(event: "changed", message: "updated default on \(id)"))
				case "note":
					try handleMetadata(rest, keyPath: \.notes, label: "note")
				case "comment":
					try handleMetadata(rest, keyPath: \.comments, label: "comment")
				case "format":
					try emit(TaskPaperOutput(taskpaper: TaskPaper.encode(document)))
				case "save":
					let destination = rest.first.map(URL.init(fileURLWithPath:)) ?? output
					try Data(TaskPaper.encode(document).utf8).write(to: destination)
					try emit(WriteOutput(written: true, output: destination.path))
				default:
					throw ValidationError("Unknown interactive command: \(command)")
			}
			return true
		} catch {
			try? emit(InteractiveError(message: "\(error)"))
			return true
		}
	}

	private mutating func handleTree(_ arguments: [String]) async throws {
		var id: String?
		var depth = 3
		var inherited = false
		var metadata = false
		var iterator = arguments.makeIterator()
		while let argument = iterator.next() {
			switch argument {
				case "--depth":
					guard let value = iterator.next(), let parsed = Int(value) else {
						throw ValidationError("--depth requires an integer.")
					}
					depth = parsed
				case "--inherited":
					inherited = true
				case "--metadata":
					metadata = true
				default:
					id = argument
			}
		}
		let resolved = try composedDocument()
		let rootID = try id ?? resolved.firstRootID()
		if inherited {
			let lemma = try await resolved.lemma(rootID)
			let root = await TreeNode.resolved(lemma, depth: depth, metadata: metadata)
			try emit(TreeOutput(root: root))
		} else {
			try emit(TreeOutput(root: resolved.ownTree(id: rootID, depth: depth, metadata: metadata)))
		}
	}

	private mutating func handleMetadata(
		_ arguments: [String],
		keyPath: WritableKeyPath<Lexicon.Graph.Node, [String]>,
		label: String
	) throws {
		let action = try arguments.required(0, named: "action")
		let id = try arguments.required(1, named: "id")
		let text = arguments.dropFirst(2).joined(separator: " ")
		try document.updateNode(id) { node in
			switch action {
				case "add":
					node[keyPath: keyPath].append(text)
				case "remove":
					node[keyPath: keyPath].removeAll { $0 == text }
				case "clear":
					node[keyPath: keyPath].removeAll()
				default:
					throw ValidationError("Unknown \(label) action: \(action)")
			}
		}
		try emit(InteractiveMessage(event: "changed", message: "updated \(label) on \(id)"))
	}

	func composedDocument() throws -> Lexicon.Document {
		let plan = try document.composed(resolving: FileLexiconImportResolver(
			baseURL: input.deletingLastPathComponent()
		))
		guard plan.conflicts.isEmpty else {
			throw ValidationError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		return plan.document
	}

	func emit<Value: Encodable>(_ value: Value) throws {
		switch format {
			case .json:
				try AgentJSON.printLine(value)
			case .text:
				print(try InteractiveText.render(value))
		}
	}
}

enum InteractiveText {
	static func render<Value: Encodable>(_ value: Value) throws -> String {
		switch value {
			case let message as InteractiveMessage:
				return "\(message.event): \(message.message)"
			case let error as InteractiveError:
				return "error: \(error.message)"
			case let help as InteractiveHelp:
				return help.commands.joined(separator: "\n")
			case let tree as TreeOutput:
				return render(tree.root)
			case let refs as RefsOutput:
				return render(refs)
			case let inspection as NodeInspection:
				return inspection.id
			case let document as DocumentInspection:
				return document.roots.joined(separator: "\n")
			case let output as WriteOutput:
				return "written: \(output.output)"
			case let output as TaskPaperOutput:
				return output.taskpaper
			default:
				return try AgentJSON.string(value, pretty: true)
		}
	}

	private static func render(_ node: TreeNode, indent: String = "") -> String {
		let children = node.children.map { render($0, indent: indent + "  ") }
		return ([indent + node.name] + children).joined(separator: "\n")
	}

	private static func render(_ refs: RefsOutput) -> String {
		let outgoing = refs.outgoing.map { "  \($0.kind) \($0.reference) -> \($0.resolved ?? "unresolved")" }
		let incoming = refs.incoming.map { "  \($0.kind) \($0.path) -> \($0.reference)" }
		return (["Outgoing:"] + outgoing + ["Incoming:"] + incoming).joined(separator: "\n")
	}
}

