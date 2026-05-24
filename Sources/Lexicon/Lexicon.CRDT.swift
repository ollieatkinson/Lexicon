//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon {

	enum CRDT: Sendable {}
}

public extension Lexicon.CRDT {

	struct OperationID: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
		public var actor: String
		public var counter: UInt64

		public init(actor: String, counter: UInt64) {
			self.actor = actor
			self.counter = counter
		}

		public static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.counter, lhs.actor) < (rhs.counter, rhs.actor)
		}

		public var description: String {
			"\(actor):\(counter)"
		}
	}

	struct Operation: Hashable, Comparable, Sendable {
		public var id: OperationID
		public var kind: Kind

		public init(_ kind: Kind, id: OperationID) {
			self.id = id
			self.kind = kind
		}

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.id < rhs.id
		}
	}

	enum Kind: Hashable, Sendable {
		case setDocumentDate(Date)
		case addDocumentNote(noteID: String, text: String)
		case removeDocumentNote(noteID: String)
		case addDocumentComment(commentID: String, text: String)
		case removeDocumentComment(commentID: String)
		case createNode(path: String, parentPath: String?, name: String)
		case renameNode(path: String, name: String)
		case deleteNode(path: String)
		case addTypeReference(path: String, type: String)
		case removeTypeReference(path: String, type: String)
		case setProtonym(path: String, protonym: String)
		case removeProtonym(path: String)
		case setDefaultValue(path: String, value: Lexicon.Graph.Node.DefaultValue)
		case removeDefaultValue(path: String)
		case addConnection(path: String, Lexicon.Import)
		case removeConnection(path: String, Lexicon.Import)
		case addNote(path: String, noteID: String, text: String)
		case removeNote(path: String, noteID: String)
		case addComment(path: String, commentID: String, text: String)
		case removeComment(path: String, commentID: String)
		case addImport(Lexicon.Import)
		case removeImport(Lexicon.Import)
	}

	struct Replica: Sendable {
		public var operations: Set<Operation>

		public init(operations: Set<Operation> = []) {
			self.operations = operations
		}

		public mutating func apply(_ operation: Operation) {
			operations.insert(operation)
		}

		public mutating func merge(_ other: Replica) {
			operations.formUnion(other.operations)
		}

		public func materialized() -> Lexicon.Document {
			State(operations: operations).document()
		}
	}
}

public extension Lexicon.CRDT.Operation {

	struct JSON: Hashable, Codable, Sendable {
		public var id: Lexicon.CRDT.OperationID
		public var kind: Lexicon.CRDT.Kind.JSON

		public init(_ operation: Lexicon.CRDT.Operation) {
			self.id = operation.id
			self.kind = Lexicon.CRDT.Kind.JSON(operation.kind)
		}
	}

	init(_ json: JSON) {
		self.init(Lexicon.CRDT.Kind(json.kind), id: json.id)
	}
}

public extension Lexicon.CRDT.Kind {

	enum JSON: Hashable, Codable, Sendable {
		case setDocumentDate(Date)
		case addDocumentNote(noteID: String, text: String)
		case removeDocumentNote(noteID: String)
		case addDocumentComment(commentID: String, text: String)
		case removeDocumentComment(commentID: String)
		case createNode(path: String, parentPath: String?, name: String)
		case renameNode(path: String, name: String)
		case deleteNode(path: String)
		case addTypeReference(path: String, type: String)
		case removeTypeReference(path: String, type: String)
		case setProtonym(path: String, protonym: String)
		case removeProtonym(path: String)
		case setDefaultValue(path: String, value: Lexicon.Graph.Node.DefaultValue.JSON)
		case removeDefaultValue(path: String)
		case addConnection(path: String, Lexicon.Import)
		case removeConnection(path: String, Lexicon.Import)
		case addNote(path: String, noteID: String, text: String)
		case removeNote(path: String, noteID: String)
		case addComment(path: String, commentID: String, text: String)
		case removeComment(path: String, commentID: String)
		case addImport(Lexicon.Import)
		case removeImport(Lexicon.Import)

		public init(_ kind: Lexicon.CRDT.Kind) {
			switch kind {
				case .setDocumentDate(let value):
					self = .setDocumentDate(value)
				case .addDocumentNote(let noteID, let text):
					self = .addDocumentNote(noteID: noteID, text: text)
				case .removeDocumentNote(let noteID):
					self = .removeDocumentNote(noteID: noteID)
				case .addDocumentComment(let commentID, let text):
					self = .addDocumentComment(commentID: commentID, text: text)
				case .removeDocumentComment(let commentID):
					self = .removeDocumentComment(commentID: commentID)
				case .createNode(let path, let parentPath, let name):
					self = .createNode(path: path, parentPath: parentPath, name: name)
				case .renameNode(let path, let name):
					self = .renameNode(path: path, name: name)
				case .deleteNode(let path):
					self = .deleteNode(path: path)
				case .addTypeReference(let path, let type):
					self = .addTypeReference(path: path, type: type)
				case .removeTypeReference(let path, let type):
					self = .removeTypeReference(path: path, type: type)
				case .setProtonym(let path, let protonym):
					self = .setProtonym(path: path, protonym: protonym)
				case .removeProtonym(let path):
					self = .removeProtonym(path: path)
				case .setDefaultValue(let path, let value):
					self = .setDefaultValue(path: path, value: .init(value))
				case .removeDefaultValue(let path):
					self = .removeDefaultValue(path: path)
				case .addConnection(let path, let value):
					self = .addConnection(path: path, value)
				case .removeConnection(let path, let value):
					self = .removeConnection(path: path, value)
				case .addNote(let path, let noteID, let text):
					self = .addNote(path: path, noteID: noteID, text: text)
				case .removeNote(let path, let noteID):
					self = .removeNote(path: path, noteID: noteID)
				case .addComment(let path, let commentID, let text):
					self = .addComment(path: path, commentID: commentID, text: text)
				case .removeComment(let path, let commentID):
					self = .removeComment(path: path, commentID: commentID)
				case .addImport(let value):
					self = .addImport(value)
				case .removeImport(let value):
					self = .removeImport(value)
			}
		}
	}

	init(_ json: JSON) {
		switch json {
			case .setDocumentDate(let value):
				self = .setDocumentDate(value)
			case .addDocumentNote(let noteID, let text):
				self = .addDocumentNote(noteID: noteID, text: text)
			case .removeDocumentNote(let noteID):
				self = .removeDocumentNote(noteID: noteID)
			case .addDocumentComment(let commentID, let text):
				self = .addDocumentComment(commentID: commentID, text: text)
			case .removeDocumentComment(let commentID):
				self = .removeDocumentComment(commentID: commentID)
			case .createNode(let path, let parentPath, let name):
				self = .createNode(path: path, parentPath: parentPath, name: name)
			case .renameNode(let path, let name):
				self = .renameNode(path: path, name: name)
			case .deleteNode(let path):
				self = .deleteNode(path: path)
			case .addTypeReference(let path, let type):
				self = .addTypeReference(path: path, type: type)
			case .removeTypeReference(let path, let type):
				self = .removeTypeReference(path: path, type: type)
			case .setProtonym(let path, let protonym):
				self = .setProtonym(path: path, protonym: protonym)
			case .removeProtonym(let path):
				self = .removeProtonym(path: path)
			case .setDefaultValue(let path, let value):
				self = .setDefaultValue(path: path, value: .init(value))
			case .removeDefaultValue(let path):
				self = .removeDefaultValue(path: path)
			case .addConnection(let path, let value):
				self = .addConnection(path: path, value)
			case .removeConnection(let path, let value):
				self = .removeConnection(path: path, value)
			case .addNote(let path, let noteID, let text):
				self = .addNote(path: path, noteID: noteID, text: text)
			case .removeNote(let path, let noteID):
				self = .removeNote(path: path, noteID: noteID)
			case .addComment(let path, let commentID, let text):
				self = .addComment(path: path, commentID: commentID, text: text)
			case .removeComment(let path, let commentID):
				self = .removeComment(path: path, commentID: commentID)
			case .addImport(let value):
				self = .addImport(value)
			case .removeImport(let value):
				self = .removeImport(value)
		}
	}
}

public extension Lexicon.CRDT.Replica {

	struct JSON: Codable, Sendable {
		public var operations: [Lexicon.CRDT.Operation.JSON]

		public init(_ replica: Lexicon.CRDT.Replica) {
			self.operations = replica.operations.sorted().map(Lexicon.CRDT.Operation.JSON.init)
		}
	}

	var json: JSON {
		JSON(self)
	}

	init(_ json: JSON) {
		self.init(operations: Set(json.operations.map(Lexicon.CRDT.Operation.init)))
	}
}

extension Lexicon.CRDT.Replica {

	init(_ document: Lexicon.Document) {
		self.init(documents: [document])
	}

	init<Documents>(documents: Documents) where Documents: Sequence, Documents.Element == Lexicon.Document {
		var builder = Lexicon.CRDT.DocumentOperationBuilder(actor: "document")
		for document in documents {
			builder.append(document)
		}
		self.init(operations: builder.operations)
	}
}

private extension Lexicon.CRDT {

	struct State: Sendable {
		var date: Register<Date>?
		var documentNotes: [String: Register<String>] = [:]
		var documentNoteRemoves: [String: OperationID] = [:]
		var documentComments: [String: Register<String>] = [:]
		var documentCommentRemoves: [String: OperationID] = [:]
		var nodes: [String: NodeState] = [:]
		var importAdds: [Lexicon.Import: OperationID] = [:]
		var importRemoves: [Lexicon.Import: OperationID] = [:]

		init(operations: Set<Operation>) {
			for operation in operations.sorted() {
				apply(operation)
			}
		}

		mutating func apply(_ operation: Operation) {
			switch operation.kind {
				case .setDocumentDate(let value):
					if operation.id >= (date?.clock ?? .zero) {
						date = .init(value: value, clock: operation.id)
					}
				case .addDocumentNote(let noteID, let text):
					documentNotes[noteID] = .init(value: text, clock: operation.id)
				case .removeDocumentNote(let noteID):
					documentNoteRemoves[noteID] = max(documentNoteRemoves[noteID], operation.id)
				case .addDocumentComment(let commentID, let text):
					documentComments[commentID] = .init(value: text, clock: operation.id)
				case .removeDocumentComment(let commentID):
					documentCommentRemoves[commentID] = max(documentCommentRemoves[commentID], operation.id)
				case .createNode(let path, let parentPath, let name):
					update(path) { $0.create(parentPath: parentPath, name: name, at: operation.id) }
				case .renameNode(let path, let name):
					update(path) { $0.rename(to: name, at: operation.id) }
				case .deleteNode(let path):
					update(path) { $0.delete(at: operation.id) }
				case .addTypeReference(let path, let type):
					update(path) { $0.add(type: type, at: operation.id) }
				case .removeTypeReference(let path, let type):
					update(path) { $0.remove(type: type, at: operation.id) }
				case .setProtonym(let path, let protonym):
					update(path) { $0.set(protonym: protonym, at: operation.id) }
				case .removeProtonym(let path):
					update(path) { $0.removeProtonym(at: operation.id) }
				case .setDefaultValue(let path, let value):
					update(path) { $0.set(defaultValue: value, at: operation.id) }
				case .removeDefaultValue(let path):
					update(path) { $0.removeDefault(at: operation.id) }
				case .addConnection(let path, let value):
					update(path) { $0.connectionAdds[value] = max($0.connectionAdds[value], operation.id) }
				case .removeConnection(let path, let value):
					update(path) { $0.connectionRemoves[value] = max($0.connectionRemoves[value], operation.id) }
				case .addNote(let path, let noteID, let text):
					update(path) { $0.notes[noteID] = .init(value: text, clock: operation.id) }
				case .removeNote(let path, let noteID):
					update(path) { $0.noteRemoves[noteID] = max($0.noteRemoves[noteID], operation.id) }
				case .addComment(let path, let commentID, let text):
					update(path) { $0.comments[commentID] = .init(value: text, clock: operation.id) }
				case .removeComment(let path, let commentID):
					update(path) { $0.commentRemoves[commentID] = max($0.commentRemoves[commentID], operation.id) }
				case .addImport(let value):
					importAdds[value] = max(importAdds[value], operation.id)
				case .removeImport(let value):
					importRemoves[value] = max(importRemoves[value], operation.id)
			}
		}

		mutating func update(_ path: String, _ body: (inout NodeState) -> Void) {
			var node = nodes[path] ?? .init(path: path)
			body(&node)
			nodes[path] = node
		}

		func document() -> Lexicon.Document {
			let visible = nodes.filter { _, node in !node.isDeleted }
			let roots = visibleChildren(parentPath: nil, visible: visible)
				.sorted { $0.name < $1.name }
				.reduce(into: [String: Lexicon.Graph.Node]()) { roots, node in
					let graphNode = build(node, visible: visible)
					roots[graphNode.name] = graphNode
				}
			let imports = importAdds
				.filter { value, add in add > (importRemoves[value] ?? .zero) }
				.map(\.key)
				.sorted { $0.reference < $1.reference }
			return .init(
				date: date?.value ?? .init(),
				roots: roots,
				imports: imports,
				notes: visibleDocumentNotes,
				comments: visibleDocumentComments
			)
		}

		func build(_ node: NodeState, visible: [String: NodeState]) -> Lexicon.Graph.Node {
			let children = visibleChildren(parentPath: node.path, visible: visible)
				.sorted { $0.name < $1.name }
				.reduce(into: [String: Lexicon.Graph.Node]()) { children, child in
					let node = build(child, visible: visible)
					children[node.name] = node
				}
			var graphNode = Lexicon.Graph.Node(
				name: node.name,
				children: children,
				type: node.types,
				defaultValue: node.defaultValue,
				connections: node.connections,
				notes: node.visibleNotes,
				comments: node.visibleComments
			)
			graphNode.protonym = node.protonym
			return graphNode
		}

		func visibleChildren(parentPath: String?, visible: [String: NodeState]) -> [NodeState] {
			visible.values
				.filter { $0.parentPath == parentPath }
				.reduce(into: [String: NodeState]()) { children, node in
					guard let existing = children[node.name] else {
						children[node.name] = node
						return
					}
					if node.identitySortKey >= existing.identitySortKey {
						children[node.name] = node
					}
				}
				.map(\.value)
		}

		var visibleDocumentNotes: [String] {
			documentNotes
				.filter { key, value in value.clock > (documentNoteRemoves[key] ?? .zero) }
				.sorted { $0.key < $1.key }
				.map(\.value.value)
		}

		var visibleDocumentComments: [String] {
			documentComments
				.filter { key, value in value.clock > (documentCommentRemoves[key] ?? .zero) }
				.sorted { $0.key < $1.key }
				.map(\.value.value)
		}
	}

	struct NodeState: Sendable {
		var path: String
		var parentPath: String?
		var parentClock: OperationID = .zero
		var name: String = ""
		var nameClock: OperationID = .zero
		var deleteClock: OperationID?
		var typeAdds: [String: OperationID] = [:]
		var typeRemoves: [String: OperationID] = [:]
		var protonym: String?
		var protonymClock: OperationID = .zero
		var defaultValue: Lexicon.Graph.Node.DefaultValue?
		var defaultClock: OperationID = .zero
		var connectionAdds: [Lexicon.Import: OperationID] = [:]
		var connectionRemoves: [Lexicon.Import: OperationID] = [:]
		var notes: [String: Register<String>] = [:]
		var noteRemoves: [String: OperationID] = [:]
		var comments: [String: Register<String>] = [:]
		var commentRemoves: [String: OperationID] = [:]

		var isDeleted: Bool {
			deleteClock.map { $0 >= max(nameClock, parentClock) } ?? false
		}

		var types: Set<String> {
			Set(typeAdds.filter { type, add in add > (typeRemoves[type] ?? .zero) }.map(\.key))
		}

		var connections: [Lexicon.Import] {
			connectionAdds
				.filter { value, add in add > (connectionRemoves[value] ?? .zero) }
				.map(\.key)
				.sorted { $0.reference < $1.reference }
		}

		var visibleNotes: [String] {
			notes
				.filter { key, value in value.clock > (noteRemoves[key] ?? .zero) }
				.sorted { $0.key < $1.key }
				.map(\.value.value)
		}

		var visibleComments: [String] {
			comments
				.filter { key, value in value.clock > (commentRemoves[key] ?? .zero) }
				.sorted { $0.key < $1.key }
				.map(\.value.value)
		}

		var identitySortKey: (OperationID, String) {
			(max(parentClock, nameClock), path)
		}

		mutating func create(parentPath: String?, name: String, at clock: OperationID) {
			if clock >= parentClock {
				self.parentPath = parentPath
				parentClock = clock
			}
			rename(to: name, at: clock)
		}

		mutating func rename(to name: String, at clock: OperationID) {
			if clock >= nameClock {
				self.name = name
				nameClock = clock
			}
		}

		mutating func delete(at clock: OperationID) {
			deleteClock = max(deleteClock, clock)
		}

		mutating func add(type: String, at clock: OperationID) {
			typeAdds[type] = max(typeAdds[type], clock)
		}

		mutating func remove(type: String, at clock: OperationID) {
			typeRemoves[type] = max(typeRemoves[type], clock)
		}

		mutating func set(protonym: String, at clock: OperationID) {
			if clock >= protonymClock {
				self.protonym = protonym
				protonymClock = clock
			}
		}

		mutating func removeProtonym(at clock: OperationID) {
			if clock >= protonymClock {
				protonym = nil
				protonymClock = clock
			}
		}

		mutating func set(defaultValue: Lexicon.Graph.Node.DefaultValue, at clock: OperationID) {
			if clock >= defaultClock {
				self.defaultValue = defaultValue
				defaultClock = clock
			}
		}

		mutating func removeDefault(at clock: OperationID) {
			if clock >= defaultClock {
				defaultValue = nil
				defaultClock = clock
			}
		}
	}

	struct Register<Value: Sendable>: Sendable {
		var value: Value
		var clock: OperationID
	}

	struct DocumentOperationBuilder {
		let actor: String
		var counter: UInt64 = 0
		var operations: Set<Operation> = []

		mutating func append(_ document: Lexicon.Document) {
			emit(.setDocumentDate(document.date))
			for note in document.notes {
				emit(.addDocumentNote(noteID: note, text: note))
			}
			for comment in document.comments {
				emit(.addDocumentComment(commentID: comment, text: comment))
			}
			for `import` in document.imports.sorted(by: { $0.reference < $1.reference }) {
				emit(.addImport(`import`))
			}
			for (name, root) in document.roots {
				append(root, path: name, parentPath: nil)
			}
		}

		mutating func append(_ node: Lexicon.Graph.Node, path: String, parentPath: String?) {
			emit(.createNode(path: path, parentPath: parentPath, name: node.name))
			for type in node.type.sorted() {
				emit(.addTypeReference(path: path, type: type))
			}
			if let protonym = node.protonym {
				emit(.setProtonym(path: path, protonym: protonym))
			}
			if let defaultValue = node.defaultValue {
				emit(.setDefaultValue(path: path, value: defaultValue))
			}
			for connection in node.connections.sorted(by: { $0.reference < $1.reference }) {
				emit(.addConnection(path: path, connection))
			}
			for note in node.notes {
				emit(.addNote(path: path, noteID: note, text: note))
			}
			for comment in node.comments {
				emit(.addComment(path: path, commentID: comment, text: comment))
			}
			for (name, child) in node.children {
				append(child, path: "\(path).\(name)", parentPath: path)
			}
		}

		mutating func emit(_ kind: Kind) {
			counter += 1
			operations.insert(.init(kind, id: .init(actor: actor, counter: counter)))
		}
	}
}

private extension Lexicon.CRDT.OperationID {
	static let zero = Self(actor: "", counter: 0)
}

private func max<T: Comparable>(_ lhs: T?, _ rhs: T) -> T {
	guard let lhs = lhs else {
		return rhs
	}
	return Swift.max(lhs, rhs)
}
