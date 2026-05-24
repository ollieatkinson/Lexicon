//
// github.com/screensailor 2022
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public extension UTType {
	static let lexicon = UTType(importedAs: "com.github.screensailor.lexicon")
	static let taskpaper = UTType(importedAs: "com.taskpaper.text")
}

public class TaskPaper {
	
	public typealias Node = Lexicon.Graph.Node
	
	public static let pattern = try! (
		line: NSRegularExpression(pattern: "^(?<tabs>\\t*)(?<content>.+)"),
		lemma: NSRegularExpression(pattern: "^(?<lemma>[\\w]+):?\\s*$"), // TODO: Optional colon `:?` allows plain text (tabbed) outlines, but this should be opted into
		operator: NSRegularExpression(pattern: "^(?<operator>[+=?])\\s*(?<content>.*\\S)?\\s*$")
	)
	
	public let string: String
	
	private var result: Result<Lexicon.Graph, Error>?
	private var documentResult: Result<Lexicon.Document, Error>?
	
	public init(_ string: String) {
		self.string = string
	}
	
	public init(_ UTF8: Data) throws {
		guard let string = String(data: UTF8, encoding: .utf8) else {
			throw "Data is not UTF-8"
		}
		self.string = string
	}
	
	public func decode() throws -> Lexicon.Graph {
		
		if let result = result {
			return try result.get()
		}
		
		do {
			let graph = try decodeDocument().graph()
			result = .success(graph)
			return graph
		} catch {
			result = .failure(error)
			throw error
		}
	}

	public func decodeDocument() throws -> Lexicon.Document {

		if let result = documentResult {
			return try result.get()
		}

		var path: [Node] = []
		var document = Lexicon.Document()
		var error: Error?
		
		string.enumerateLines{ line, stop in
			do {
				guard let match = TaskPaper.pattern.line.firstMatch(in: line, options: [], range: line.nsRange) else {
					return
				}
				let range = match.range(withName: "content")
				let content = line.substring(with: range)
				let depth = match.range(withName: "tabs").length
				try self.decode(line: content, depth: depth, path: &path, document: &document)
			} catch let o {
				stop = true
				error = o
			}
		}
		
		while path.count > 1 {
			reduce(&path)
		}
		if let root = path.popLast() {
			document.roots[root.name] = root
		}

		if let error = error {
			documentResult = .failure(error)
			throw error
		}
		
		documentResult = .success(document)
		return document
	}
	
	func reduce(_ path: inout [Node]) {
		let child = path.removeLast()
		path[path.endIndex - 1].children[child.name] = child
	}
	
	func decode(line: String, depth: Int, path: inout [Node], document: inout Lexicon.Document) throws {

		if line.hasPrefix("@ ") {
			if path.isEmpty {
				document.imports.append(.init(String(line.dropFirst(2))))
			} else if depth == 0 {
				finishCurrentRoot(path: &path, document: &document)
				document.imports.append(.init(String(line.dropFirst(2))))
			} else {
				try focus(depth: depth, path: &path, line: line)
				path[path.endIndex - 1].connections.append(.init(String(line.dropFirst(2))))
			}
			return
		}

		if line.hasPrefix("# ") {
			if path.isEmpty {
				document.comments.append(String(line.dropFirst(2)))
			} else {
				try focus(depth: depth, path: &path, line: line)
				path[path.endIndex - 1].comments.append(String(line.dropFirst(2)))
			}
			return
		}

		if line.hasPrefix("> ") {
			if path.isEmpty {
				document.notes.append(String(line.dropFirst(2)))
			} else {
				try focus(depth: depth, path: &path, line: line)
				path[path.endIndex - 1].notes.append(String(line.dropFirst(2)))
			}
			return
		}
		
		let name = TaskPaper.pattern.lemma.first(in: line)?["lemma"]
		
		guard path.isNotEmpty else {
			guard let name = name, depth == 0 else {
				return // ignore everything before the first root node
			}
			path = [Node(name: name)]
			return
		}
		
		if let name = name {

			if depth == 0 {
				finishCurrentRoot(path: &path, document: &document)
				path = [Node(name: name)]
				return
			}
			
			let indent = depth - (path.count - 1)
			
			switch indent {
					
				case 1: // child
					break

				case 0: // sibling
					reduce(&path)

				case ..<0: // ancestor
					guard path.count + indent > 0 else {
						throw "Line with wrong indent (\(indent)): '\(line)'"
					}
					for _ in 0...abs(indent) {
						reduce(&path)
					}
					
				default:
					throw "Line with wrong indent (\(indent)): '\(line)'"
			}
			
			path.append(Node(name: name))
		}
		
		else if
			let match = TaskPaper.pattern.operator.first(in: line),
			let symbol = match["operator"],
			let content = match["content"]
		{
			switch symbol {
				case "+":
					try focus(depth: depth, path: &path, line: line)
					path[path.endIndex - 1].type.insert(content)
				case "=":
					try focus(depth: depth, path: &path, line: line)
					path[path.endIndex - 1].protonym = content
				case "?":
					try focus(depth: depth, path: &path, line: line)
					path[path.endIndex - 1].defaultValue = Self.defaultValue(from: content)
				default: break
			}
		}
	}

	func finishCurrentRoot(path: inout [Node], document: inout Lexicon.Document) {
		while path.count > 1 {
			reduce(&path)
		}
		if let root = path.popLast() {
			document.roots[root.name] = root
		}
	}

	func focus(depth: Int, path: inout [Node], line: String) throws {
		guard depth < path.count else {
			return
		}
		while path.count > depth + 1 {
			reduce(&path)
		}
	}
}

public extension TaskPaper {
	
	static func encode(_ node: Lexicon.Graph.Node, date: Date = .init()) -> String {
		encode(Lexicon.Graph(root: node, date: date))
	}
	
	static func encode(_ graph: Lexicon.Graph) -> String {
		encode(Lexicon.Document(graph))
	}

	static func encode(_ document: Lexicon.Document) -> String {
		
		var lines: [String] = []
		
		for comment in document.comments {
			lines.append("# \(comment)")
		}
		for note in document.notes {
			lines.append("> \(note)")
		}
		for `import` in document.imports.sorted(by: { $0.reference < $1.reference }) {
			lines.append("@ \(`import`.reference)")
		}

		for root in document.roots.values {
			root.traverse(sorted: true) { id, name, node in
				let depth = id.reduce(0){ a, e in e == "." ? a + 1 : a }
				let tabs = "\t" * depth
				lines.append("\(tabs)\(name):")
				for comment in node.comments {
					lines.append("\(tabs)# \(comment)")
				}
				for note in node.notes {
					lines.append("\(tabs)> \(note)")
				}
				if let defaultValue = node.defaultValue {
					lines.append("\(tabs)? \(Self.encode(defaultValue))")
				}
				for connection in node.connections.sorted(by: { $0.reference < $1.reference }) {
					lines.append("\(tabs)@ \(connection.reference)")
				}
				if let protonym = node.protonym {
					lines.append("\(tabs)= \(protonym)")
				} else {
					for type in node.type.sorted(by: <) { // TODO: consider whether to sort it lexicographically
						lines.append("\(tabs)+ \(type)")
					}
				}
			}
		}
		
		return lines.joined(separator: "\n")
	}
}

private extension TaskPaper {

	static func defaultValue(from content: String?) -> Lexicon.Graph.Node.DefaultValue {
		let content = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if content.hasPrefix("@") {
			let id = content.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
			return .reference(id)
		} else {
			return .literal(.parse(content))
		}
	}

	static func encode(_ value: Lexicon.Graph.Node.DefaultValue) -> String {
		switch value {
			case .reference(let id):
				return "@ \(id)"
			case .literal(let value):
				return encode(value)
		}
	}

	static func encode(_ value: JSONValue) -> String {
		guard
			let data = try? JSONSerialization.data(
				withJSONObject: value.jsonObject,
				options: [.fragmentsAllowed, .sortedKeys]
			),
			let string = String(data: data, encoding: .utf8)
		else {
			return ""
		}
		return string
	}
}
