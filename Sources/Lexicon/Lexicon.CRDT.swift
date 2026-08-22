//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon {

	enum CRDT {
		public struct OperationID: Hashable, Comparable, Codable, Sendable,
			CustomStringConvertible {

			public var timestamp: UInt64
			public var actor: String

			public init(timestamp: UInt64, actor: String) {
				self.timestamp = timestamp
				self.actor = actor
			}

			public static let zero = Self(timestamp: 0, actor: "")

			public static func < (lhs: Self, rhs: Self) -> Bool {
				(lhs.timestamp, lhs.actor) < (rhs.timestamp, rhs.actor)
			}

			public var description: String {
				"\(timestamp)@\(actor)"
			}
		}

		public struct Operation: Hashable, Sendable {
			public var id: OperationID
			public var kind: Kind

			public init(_ kind: Kind, id: OperationID) {
				self.id = id
				self.kind = kind
			}
		}

		public enum Kind: Hashable, Sendable {
			case setDocumentDate(Date)
			case insertDocumentNote(after: OperationID?, text: String)
			case removeDocumentNote(element: OperationID)
			case insertDocumentComment(after: OperationID?, text: String)
			case removeDocumentComment(element: OperationID)
			case insertImport(after: OperationID?, value: Lexicon.Import)
			case removeImport(element: OperationID)
			case createNode(path: Lemma.ID, parentPath: Lemma.ID?, name: Lemma.Name)
			case renameNode(path: Lemma.ID, name: Lemma.Name)
			case deleteNode(path: Lemma.ID)
			case addTypeReference(path: Lemma.ID, type: Lemma.ID)
			case removeTypeReference(path: Lemma.ID, type: Lemma.ID)
			case setProtonym(path: Lemma.ID, protonym: Lemma.RelativeID)
			case removeProtonym(path: Lemma.ID)
			case setDefaultValue(path: Lemma.ID, value: Lexicon.Graph.Node.DefaultValue)
			case removeDefaultValue(path: Lemma.ID)
			case insertConnection(
				path: Lemma.ID,
				after: OperationID?,
				value: Lexicon.Import
			)
			case removeConnection(path: Lemma.ID, element: OperationID)
			case insertNote(path: Lemma.ID, after: OperationID?, text: String)
			case removeNote(path: Lemma.ID, element: OperationID)
			case insertComment(path: Lemma.ID, after: OperationID?, text: String)
			case removeComment(path: Lemma.ID, element: OperationID)
		}

		public enum ReplicaError: Error, Hashable, Sendable, CustomStringConvertible,
			LocalizedError {

			case operationIDCollision(OperationID)
			case invalidOperation(String)

			public var description: String {
				switch self {
					case .operationIDCollision(let id):
						return "Operation ID '\(id)' was reused with a different payload"
					case .invalidOperation(let message):
						return message
				}
			}

			public var errorDescription: String? {
				description
			}
		}

		/// A validated document together with the stable CRDT addresses of its
		/// currently visible nodes.
		///
		/// Operation `path` values are creation-time node addresses. They do not
		/// change when a node or one of its ancestors is renamed. Use this value
		/// to translate between those stable addresses and paths in the current
		/// materialized document.
		public struct Materialization: Sendable {
			public let document: Lexicon.Document
			public let materializedPathsByNodeAddress: [Lemma.ID: Lemma.ID]

			init(
				document: Lexicon.Document,
				materializedPathsByNodeAddress: [Lemma.ID: Lemma.ID]
			) {
				self.document = document
				self.materializedPathsByNodeAddress = materializedPathsByNodeAddress
			}

			public func materializedPath(
				forNodeAddress address: Lemma.ID
			) -> Lemma.ID? {
				materializedPathsByNodeAddress[address]
			}

			public func nodeAddress(
				forMaterializedPath path: Lemma.ID
			) -> Lemma.ID? {
				materializedPathsByNodeAddress.keys.sorted().first {
					materializedPathsByNodeAddress[$0] == path
				}
			}
		}

		public struct Replica: Sendable {
			public private(set) var operations: [OperationID: Operation]

			public init() {
				self.operations = [:]
			}

			public init<Operations>(operations: Operations) throws
			where Operations: Sequence, Operations.Element == Operation {
				var candidate: [OperationID: Operation] = [:]
				for operation in operations {
					try Self.insert(operation, into: &candidate)
				}
				try Self.validate(candidate)
				self.operations = candidate
			}

			/// Identical replay is a no-op. Reusing an ID for another payload
			/// throws before the replica is changed.
			public mutating func apply(_ operation: Operation) throws {
				var candidate = operations
				try Self.insert(operation, into: &candidate)
				try Self.validate(candidate)
				operations = candidate
			}

			/// Merges and validates the complete candidate before publishing it.
			public mutating func merge(_ other: Self) throws {
				var candidate = operations
				for operation in other.operations.values.sorted(by: { $0.id < $1.id }) {
					try Self.insert(operation, into: &candidate)
				}
				try Self.validate(candidate)
				operations = candidate
			}

			public func materialized() throws -> Lexicon.Document {
				try materialization().document
			}

			public func materialization() throws -> Materialization {
				try Self.materialize(operations)
			}

			private static func insert(
				_ operation: Operation,
				into operations: inout [OperationID: Operation]
			) throws {
				if let existing = operations[operation.id] {
					guard existing == operation else {
						throw ReplicaError.operationIDCollision(operation.id)
					}
					return
				}
				operations[operation.id] = operation
			}

			private static func validate(
				_ operations: [OperationID: Operation]
			) throws {
				try validateOperationStructure(operations)
				_ = try materialize(operations)
			}

			private static func materialize(
				_ operations: [OperationID: Operation]
			) throws -> Materialization {
				if operations.isEmpty {
					return Materialization(
						document: Lexicon.Document(),
						materializedPathsByNodeAddress: [:]
					)
				}
				let materialization = try State(operations: operations).materialization()
				if materialization.document.roots.isEmpty {
					throw ReplicaError.invalidOperation(
						"A non-empty replica must materialize at least one root"
					)
				}
				return Materialization(
					document: try materialization.document.validated(),
					materializedPathsByNodeAddress:
						materialization.materializedPathsByNodeAddress
				)
			}
		}
	}
}

public extension Lexicon.CRDT.Kind {

	enum JSON: Hashable, Codable, Sendable {
		case setDocumentDate(Date)
		case insertDocumentNote(after: Lexicon.CRDT.OperationID?, text: String)
		case removeDocumentNote(element: Lexicon.CRDT.OperationID)
		case insertDocumentComment(after: Lexicon.CRDT.OperationID?, text: String)
		case removeDocumentComment(element: Lexicon.CRDT.OperationID)
		case insertImport(
			after: Lexicon.CRDT.OperationID?,
			value: Lexicon.Import
		)
		case removeImport(element: Lexicon.CRDT.OperationID)
		case createNode(path: Lemma.ID, parentPath: Lemma.ID?, name: Lemma.Name)
		case renameNode(path: Lemma.ID, name: Lemma.Name)
		case deleteNode(path: Lemma.ID)
		case addTypeReference(path: Lemma.ID, type: Lemma.ID)
		case removeTypeReference(path: Lemma.ID, type: Lemma.ID)
		case setProtonym(path: Lemma.ID, protonym: Lemma.RelativeID)
		case removeProtonym(path: Lemma.ID)
		case setDefaultValue(
			path: Lemma.ID,
			value: Lexicon.Graph.Node.DefaultValue.JSON
		)
		case removeDefaultValue(path: Lemma.ID)
		case insertConnection(
			path: Lemma.ID,
			after: Lexicon.CRDT.OperationID?,
			value: Lexicon.Import
		)
		case removeConnection(path: Lemma.ID, element: Lexicon.CRDT.OperationID)
		case insertNote(
			path: Lemma.ID,
			after: Lexicon.CRDT.OperationID?,
			text: String
		)
		case removeNote(path: Lemma.ID, element: Lexicon.CRDT.OperationID)
		case insertComment(
			path: Lemma.ID,
			after: Lexicon.CRDT.OperationID?,
			text: String
		)
		case removeComment(path: Lemma.ID, element: Lexicon.CRDT.OperationID)

		public init(_ kind: Lexicon.CRDT.Kind) {
			switch kind {
				case .setDocumentDate(let value):
					self = .setDocumentDate(value)
				case .insertDocumentNote(let after, let text):
					self = .insertDocumentNote(after: after, text: text)
				case .removeDocumentNote(let element):
					self = .removeDocumentNote(element: element)
				case .insertDocumentComment(let after, let text):
					self = .insertDocumentComment(after: after, text: text)
				case .removeDocumentComment(let element):
					self = .removeDocumentComment(element: element)
				case .insertImport(let after, let value):
					self = .insertImport(after: after, value: value)
				case .removeImport(let element):
					self = .removeImport(element: element)
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
				case .insertConnection(let path, let after, let value):
					self = .insertConnection(path: path, after: after, value: value)
				case .removeConnection(let path, let element):
					self = .removeConnection(path: path, element: element)
				case .insertNote(let path, let after, let text):
					self = .insertNote(path: path, after: after, text: text)
				case .removeNote(let path, let element):
					self = .removeNote(path: path, element: element)
				case .insertComment(let path, let after, let text):
					self = .insertComment(path: path, after: after, text: text)
				case .removeComment(let path, let element):
					self = .removeComment(path: path, element: element)
			}
		}
	}

	init(_ json: JSON) {
		switch json {
			case .setDocumentDate(let value):
				self = .setDocumentDate(value)
			case .insertDocumentNote(let after, let text):
				self = .insertDocumentNote(after: after, text: text)
			case .removeDocumentNote(let element):
				self = .removeDocumentNote(element: element)
			case .insertDocumentComment(let after, let text):
				self = .insertDocumentComment(after: after, text: text)
			case .removeDocumentComment(let element):
				self = .removeDocumentComment(element: element)
			case .insertImport(let after, let value):
				self = .insertImport(after: after, value: value)
			case .removeImport(let element):
				self = .removeImport(element: element)
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
			case .insertConnection(let path, let after, let value):
				self = .insertConnection(path: path, after: after, value: value)
			case .removeConnection(let path, let element):
				self = .removeConnection(path: path, element: element)
			case .insertNote(let path, let after, let text):
				self = .insertNote(path: path, after: after, text: text)
			case .removeNote(let path, let element):
				self = .removeNote(path: path, element: element)
			case .insertComment(let path, let after, let text):
				self = .insertComment(path: path, after: after, text: text)
			case .removeComment(let path, let element):
				self = .removeComment(path: path, element: element)
		}
	}
}

public extension Lexicon.CRDT.Operation {

	struct JSON: Hashable, Codable, Sendable {
		public var id: Lexicon.CRDT.OperationID
		public var kind: Lexicon.CRDT.Kind.JSON

		public init(_ operation: Lexicon.CRDT.Operation) {
			self.id = operation.id
			self.kind = .init(operation.kind)
		}
	}

	init(_ json: JSON) {
		self.init(.init(json.kind), id: json.id)
	}
}

public extension Lexicon.CRDT.Replica {

	struct JSON: Codable, Sendable {
		public var operations: [Lexicon.CRDT.Operation.JSON]

		public init(_ replica: Lexicon.CRDT.Replica) {
			self.operations = replica.operations.values
				.sorted { $0.id < $1.id }
				.map(Lexicon.CRDT.Operation.JSON.init)
		}
	}

	var json: JSON {
		JSON(self)
	}

	init(_ json: JSON) throws {
		try self.init(operations: json.operations.map(Lexicon.CRDT.Operation.init))
	}

	init(_ document: Lexicon.Document) throws {
		var builder = Lexicon.CRDT.DocumentOperationBuilder(actor: "document")
		builder.append(document)
		try self.init(operations: builder.operations)
	}
}

private extension Lexicon.CRDT.Replica {

	enum ListScope: Hashable {
		case documentNote
		case documentComment
		case documentImport
		case connection(Lemma.ID)
		case note(Lemma.ID)
		case comment(Lemma.ID)
	}

	static func validateOperationStructure(
		_ operations: [Lexicon.CRDT.OperationID: Lexicon.CRDT.Operation]
	) throws {
		let created = Set(operations.values.compactMap { operation -> Lemma.ID? in
			if case .createNode(let path, _, _) = operation.kind {
				return path
			}
			return nil
		})
		var insertions: [Lexicon.CRDT.OperationID: ListScope] = [:]
		var listReferences: [
			(scope: ListScope, operation: Lexicon.CRDT.OperationID, reference: Lexicon.CRDT.OperationID)
		] = []

		func requireNode(_ path: Lemma.ID) throws {
			guard created.contains(path) else {
				throw Lexicon.CRDT.ReplicaError.invalidOperation(
					"Operation targets node '\(path)' without a create operation"
				)
			}
		}

		func insert(
			_ operation: Lexicon.CRDT.Operation,
			scope: ListScope,
			after: Lexicon.CRDT.OperationID?
		) {
			insertions[operation.id] = scope
			if let after {
				listReferences.append((scope, operation.id, after))
			}
		}

		for operation in operations.values.sorted(by: { $0.id < $1.id }) {
			switch operation.kind {
				case .setDocumentDate:
					break
				case .insertDocumentNote(let after, _):
					insert(operation, scope: .documentNote, after: after)
				case .removeDocumentNote(let element):
					listReferences.append((.documentNote, operation.id, element))
				case .insertDocumentComment(let after, _):
					insert(operation, scope: .documentComment, after: after)
				case .removeDocumentComment(let element):
					listReferences.append((.documentComment, operation.id, element))
				case .insertImport(let after, _):
					insert(operation, scope: .documentImport, after: after)
				case .removeImport(let element):
					listReferences.append((.documentImport, operation.id, element))
				case .createNode(let path, let parentPath, let name):
					guard path.name == name, path.parent == parentPath else {
						throw Lexicon.CRDT.ReplicaError.invalidOperation(
							"Create operation path '\(path)' does not match its parent/name"
						)
					}
					if let parentPath, !created.contains(parentPath) {
						throw Lexicon.CRDT.ReplicaError.invalidOperation(
							"Create operation for '\(path)' is missing parent '\(parentPath)'"
						)
					}
				case .renameNode(let path, _),
					.deleteNode(let path),
					.removeProtonym(let path),
					.removeDefaultValue(let path):
					try requireNode(path)
				case .addTypeReference(let path, _),
					.removeTypeReference(let path, _):
					try requireNode(path)
				case .setProtonym(let path, _):
					try requireNode(path)
				case .setDefaultValue(let path, _):
					try requireNode(path)
				case .insertConnection(let path, let after, _):
					try requireNode(path)
					insert(operation, scope: .connection(path), after: after)
				case .removeConnection(let path, let element):
					try requireNode(path)
					listReferences.append((.connection(path), operation.id, element))
				case .insertNote(let path, let after, _):
					try requireNode(path)
					insert(operation, scope: .note(path), after: after)
				case .removeNote(let path, let element):
					try requireNode(path)
					listReferences.append((.note(path), operation.id, element))
				case .insertComment(let path, let after, _):
					try requireNode(path)
					insert(operation, scope: .comment(path), after: after)
				case .removeComment(let path, let element):
					try requireNode(path)
					listReferences.append((.comment(path), operation.id, element))
			}
		}

		for item in listReferences {
			guard insertions[item.reference] == item.scope else {
				throw Lexicon.CRDT.ReplicaError.invalidOperation(
					"List operation '\(item.operation)' references an element from another or missing list"
				)
			}
		}
	}
}

private extension Lexicon.CRDT {

	struct Register<Value: Sendable>: Sendable {
		var value: Value
		var clock: OperationID
	}

	struct RGA<Value: Sendable>: Sendable {
		struct Insertion: Sendable {
			var after: OperationID?
			var value: Value
		}

		var insertions: [OperationID: Insertion] = [:]
		var removals: Set<OperationID> = []

		mutating func insert(
			id: OperationID,
			after: OperationID?,
			value: Value
		) {
			insertions[id] = .init(after: after, value: value)
		}

		func values(after lowerBound: OperationID? = nil) -> [Value] {
			var followers: [OperationID?: [OperationID]] = [:]
			for (id, insertion) in insertions {
				followers[insertion.after, default: []].append(id)
			}
			for key in followers.keys {
				followers[key]?.sort()
			}
			var result: [Value] = []
			var visited: Set<OperationID> = []

			func append(after predecessor: OperationID?) {
				for id in followers[predecessor, default: []] where visited.insert(id).inserted {
					if
						lowerBound.map({ id > $0 }) ?? true,
						!removals.contains(id),
						let insertion = insertions[id]
					{
						result.append(insertion.value)
					}
					append(after: id)
				}
			}

			append(after: nil)
			// A complete validated replica has no orphans; retaining this
				// deterministic fallback keeps diagnostics/materialization total.
				for id in insertions.keys.sorted() where visited.insert(id).inserted {
					if
						lowerBound.map({ id > $0 }) ?? true,
						!removals.contains(id),
						let insertion = insertions[id]
					{
						result.append(insertion.value)
					}
					append(after: id)
			}
			return result
		}
	}

	struct State: Sendable {
		var date: Register<Date>?
		var documentNotes = RGA<String>()
		var documentComments = RGA<String>()
		var imports = RGA<Lexicon.Import>()
		var nodes: [Lemma.ID: NodeState] = [:]

		init(operations: [OperationID: Operation]) {
			for operation in operations.values.sorted(by: { $0.id < $1.id }) {
				apply(operation)
			}
		}

		mutating func apply(_ operation: Operation) {
			switch operation.kind {
				case .setDocumentDate(let value):
					if operation.id >= (date?.clock ?? .zero) {
						date = .init(value: value, clock: operation.id)
					}
				case .insertDocumentNote(let after, let text):
					documentNotes.insert(id: operation.id, after: after, value: text)
				case .removeDocumentNote(let element):
					documentNotes.removals.insert(element)
				case .insertDocumentComment(let after, let text):
					documentComments.insert(id: operation.id, after: after, value: text)
				case .removeDocumentComment(let element):
					documentComments.removals.insert(element)
				case .insertImport(let after, let value):
					imports.insert(id: operation.id, after: after, value: value)
				case .removeImport(let element):
					imports.removals.insert(element)
				case .createNode(let path, let parentPath, let name):
					update(path) {
						$0.create(parentPath: parentPath, name: name, at: operation.id)
					}
				case .renameNode(let path, let name):
					update(path) { $0.rename(to: name, at: operation.id) }
				case .deleteNode(let path):
					update(path) { $0.delete(at: operation.id) }
				case .addTypeReference(let path, let type):
					update(path) { $0.typeAdds[type] = max($0.typeAdds[type], operation.id) }
				case .removeTypeReference(let path, let type):
					update(path) {
						$0.typeRemoves[type] = max($0.typeRemoves[type], operation.id)
					}
				case .setProtonym(let path, let protonym):
					update(path) {
						if operation.id >= ($0.protonym?.clock ?? .zero) {
							$0.protonym = .init(value: protonym, clock: operation.id)
						}
					}
				case .removeProtonym(let path):
					update(path) { $0.protonymRemoval = max($0.protonymRemoval, operation.id) }
				case .setDefaultValue(let path, let value):
					update(path) {
						if operation.id >= ($0.defaultValue?.clock ?? .zero) {
							$0.defaultValue = .init(value: value, clock: operation.id)
						}
					}
				case .removeDefaultValue(let path):
					update(path) {
						$0.defaultValueRemoval = max($0.defaultValueRemoval, operation.id)
					}
				case .insertConnection(let path, let after, let value):
					update(path) {
						$0.connections.insert(
							id: operation.id,
							after: after,
							value: value
						)
					}
				case .removeConnection(let path, let element):
					update(path) { $0.connections.removals.insert(element) }
				case .insertNote(let path, let after, let text):
					update(path) {
						$0.notes.insert(id: operation.id, after: after, value: text)
					}
				case .removeNote(let path, let element):
					update(path) { $0.notes.removals.insert(element) }
				case .insertComment(let path, let after, let text):
					update(path) {
						$0.comments.insert(id: operation.id, after: after, value: text)
					}
				case .removeComment(let path, let element):
					update(path) { $0.comments.removals.insert(element) }
			}
		}

		mutating func update(
			_ path: Lemma.ID,
			_ body: (inout NodeState) -> Void
		) {
			var node = nodes[path] ?? .init(path: path)
			body(&node)
			nodes[path] = node
		}

		func isVisible(_ node: NodeState) -> Bool {
			guard var creation = node.creation, !node.isDeleted else {
				return false
			}
			var parentPath = node.parentPath
			while let path = parentPath {
				guard
					let parent = nodes[path],
					let parentCreation = parent.creation,
					!parent.isDeleted,
					creation.clock > parentCreation.clock
				else {
					return false
				}
				creation = parentCreation
				parentPath = parent.parentPath
			}
			return true
		}

		func materialization() throws -> Materialization {
			let visible = nodes.filter { isVisible($0.value) }
			for path in visible.keys.sorted() {
				guard let node = visible[path] else {
					continue
				}
				if let parent = node.parentPath, visible[parent] == nil {
					throw ReplicaError.invalidOperation(
						"Visible node '\(path)' is missing parent '\(parent)'"
					)
				}
			}

			let rootStates = visible
				.filter { $0.value.parentPath == nil }
				.map(\.value)
				.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
			try rejectDuplicateNames(rootStates, parent: nil)
			for parent in visible.keys.sorted() {
				let children = visible.values
					.filter { $0.parentPath == parent }
					.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
				try rejectDuplicateNames(children, parent: parent)
			}

			let materializedPaths = try materializedPaths(for: visible)
			var roots: [Lemma.Name: Lexicon.Graph.Node] = [:]
			for root in rootStates {
				roots[root.name] = try build(
					root,
					visible: visible,
					materializedPaths: materializedPaths
				)
			}
			return Materialization(
				document: .init(
					date: date?.value ?? Lexicon.Document.unspecifiedDate,
					roots: roots,
					imports: imports.values(),
					notes: documentNotes.values(),
					comments: documentComments.values()
				),
				materializedPathsByNodeAddress: materializedPaths
			)
		}

		func build(
			_ state: NodeState,
			visible: [Lemma.ID: NodeState],
			materializedPaths: [Lemma.ID: Lemma.ID]
		) throws -> Lexicon.Graph.Node {
			let childStates = visible.values
				.filter { $0.parentPath == state.path }
				.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
			var children: [Lemma.Name: Lexicon.Graph.Node] = [:]
			for child in childStates {
				children[child.name] = try build(
					child,
					visible: visible,
					materializedPaths: materializedPaths
				)
			}

			let types = try Set(state.visibleTypes.map { address in
				guard let path = materializedPaths[address] else {
					throw ReplicaError.invalidOperation(
						"Node '\(state.path)' references missing type address '\(address)'"
					)
				}
				return path
			})
			let protonym = try materializedProtonym(
				for: state,
				materializedPaths: materializedPaths
			)
			let defaultValue = try materializedDefaultValue(
				for: state,
				materializedPaths: materializedPaths
			)

			return .init(
				children: children,
				type: types,
				protonym: protonym,
				defaultValue: defaultValue,
				connections: state.connections.values(after: state.creation?.clock),
				notes: state.notes.values(after: state.creation?.clock),
				comments: state.comments.values(after: state.creation?.clock)
			)
		}

		func materializedPaths(
			for visible: [Lemma.ID: NodeState]
		) throws -> [Lemma.ID: Lemma.ID] {
			var result: [Lemma.ID: Lemma.ID] = [:]
			let ordered = visible.values.sorted {
				($0.path.components.count, $0.path) <
					($1.path.components.count, $1.path)
			}
			for state in ordered {
				if let parentAddress = state.parentPath {
					guard let parentPath = result[parentAddress] else {
						throw ReplicaError.invalidOperation(
							"Visible node '\(state.path)' is missing parent '\(parentAddress)'"
						)
					}
					result[state.path] = parentPath.appending(state.name)
				} else {
					result[state.path] = Lemma.ID(root: state.name)
				}
			}
			return result
		}

		func materializedProtonym(
			for state: NodeState,
			materializedPaths: [Lemma.ID: Lemma.ID]
		) throws -> Lemma.RelativeID? {
			guard let protonym = state.visibleProtonym else {
				return nil
			}
			guard
				let parentAddress = state.parentPath,
				let parentPath = materializedPaths[parentAddress]
			else {
				throw ReplicaError.invalidOperation(
					"Root node address '\(state.path)' cannot declare a protonym"
				)
			}
			let targetAddress = parentAddress.appending(protonym)
			guard let targetPath = materializedPaths[targetAddress] else {
				throw ReplicaError.invalidOperation(
					"Node '\(state.path)' references missing protonym address '\(targetAddress)'"
				)
			}
			do {
				return try targetPath.relative(to: parentPath)
			} catch {
				throw ReplicaError.invalidOperation(
					"Node '\(state.path)' has a protonym outside its materialized parent"
				)
			}
		}

		func materializedDefaultValue(
			for state: NodeState,
			materializedPaths: [Lemma.ID: Lemma.ID]
		) throws -> Lexicon.Graph.Node.DefaultValue? {
			guard case .reference(let address) = state.visibleDefaultValue else {
				return state.visibleDefaultValue
			}
			guard let path = materializedPaths[address] else {
				throw ReplicaError.invalidOperation(
					"Node '\(state.path)' references missing default-value address '\(address)'"
				)
			}
			return .reference(path)
		}

		func rejectDuplicateNames(
			_ states: [NodeState],
			parent: Lemma.ID?
		) throws {
			var names: Set<Lemma.Name> = []
			for state in states where !names.insert(state.name).inserted {
				throw ReplicaError.invalidOperation(
					"Multiple visible nodes declare '\(state.name)' below '\(parent?.description ?? "<document>")'"
				)
			}
		}
	}

	struct NodeState: Sendable {
		var path: Lemma.ID
		var creation: Register<Creation>?
		var rename: Register<Lemma.Name>?
		var deletion: OperationID?
		var typeAdds: [Lemma.ID: OperationID] = [:]
		var typeRemoves: [Lemma.ID: OperationID] = [:]
		var protonym: Register<Lemma.RelativeID>?
		var protonymRemoval: OperationID?
		var defaultValue: Register<Lexicon.Graph.Node.DefaultValue>?
		var defaultValueRemoval: OperationID?
		var connections = RGA<Lexicon.Import>()
		var notes = RGA<String>()
		var comments = RGA<String>()

		struct Creation: Sendable {
			var parentPath: Lemma.ID?
			var name: Lemma.Name
		}

		init(path: Lemma.ID) {
			self.path = path
		}

		mutating func create(
			parentPath: Lemma.ID?,
			name: Lemma.Name,
			at clock: OperationID
		) {
			if clock >= (creation?.clock ?? .zero) {
				creation = .init(
					value: .init(parentPath: parentPath, name: name),
					clock: clock
				)
			}
		}

		mutating func rename(to name: Lemma.Name, at clock: OperationID) {
			if clock >= (rename?.clock ?? .zero) {
				rename = .init(value: name, clock: clock)
			}
		}

		mutating func delete(at clock: OperationID) {
			deletion = max(deletion, clock)
		}

		var isDeleted: Bool {
			guard let creation else {
				return true
			}
			return (deletion ?? .zero) >= creation.clock
		}

		var parentPath: Lemma.ID? {
			creation?.value.parentPath
		}

		var name: Lemma.Name {
			guard let creation else {
				return path.name
			}
			if let rename, rename.clock > creation.clock {
				return rename.value
			}
			return creation.value.name
		}

		var visibleTypes: Set<Lemma.ID> {
			guard let creation else {
				return []
			}
			return Set(typeAdds.compactMap { type, add in
				add > creation.clock && add > (typeRemoves[type] ?? .zero) ? type : nil
			})
		}

		var visibleProtonym: Lemma.RelativeID? {
			guard
				let creation,
				let protonym,
				protonym.clock > creation.clock,
				protonym.clock > (protonymRemoval ?? .zero)
			else {
				return nil
			}
			return protonym.value
		}

		var visibleDefaultValue: Lexicon.Graph.Node.DefaultValue? {
			guard
				let creation,
				let defaultValue,
				defaultValue.clock > creation.clock,
				defaultValue.clock > (defaultValueRemoval ?? .zero)
			else {
				return nil
			}
			return defaultValue.value
		}
	}

	struct DocumentOperationBuilder {
		var actor: String
		var timestamp: UInt64 = 0
		var operations: [Operation] = []

		mutating func append(_ document: Lexicon.Document) {
			emit(.setDocumentDate(document.date))

			var previous: OperationID?
			for note in document.notes {
				previous = emit(.insertDocumentNote(after: previous, text: note))
			}
			previous = nil
			for comment in document.comments {
				previous = emit(.insertDocumentComment(after: previous, text: comment))
			}
			previous = nil
			for `import` in document.imports {
				previous = emit(.insertImport(after: previous, value: `import`))
			}

			for (rootName, root) in document.roots {
				append(
					root,
					name: rootName,
					path: Lemma.ID(root: rootName),
					parentPath: nil
				)
			}
		}

		mutating func append(
			_ node: Lexicon.Graph.Node,
			name: Lemma.Name,
			path: Lemma.ID,
			parentPath: Lemma.ID?
		) {
			emit(.createNode(path: path, parentPath: parentPath, name: name))
			for type in node.type.sorted() {
				emit(.addTypeReference(path: path, type: type))
			}
			if let protonym = node.protonym {
				emit(.setProtonym(path: path, protonym: protonym))
			}
			if let defaultValue = node.defaultValue {
				emit(.setDefaultValue(path: path, value: defaultValue))
			}

			var previous: OperationID?
			for connection in node.connections {
				previous = emit(.insertConnection(
					path: path,
					after: previous,
					value: connection
				))
			}
			previous = nil
			for note in node.notes {
				previous = emit(.insertNote(path: path, after: previous, text: note))
			}
			previous = nil
			for comment in node.comments {
				previous = emit(.insertComment(
					path: path,
					after: previous,
					text: comment
				))
			}
			for (childName, child) in node.children {
				append(
					child,
					name: childName,
					path: path.appending(childName),
					parentPath: path
				)
			}
		}

		@discardableResult
		mutating func emit(_ kind: Kind) -> OperationID {
			timestamp += 1
			let id = OperationID(timestamp: timestamp, actor: actor)
			operations.append(.init(kind, id: id))
			return id
		}
	}
}

private func max<T: Comparable>(_ lhs: T?, _ rhs: T) -> T {
	guard let lhs else {
		return rhs
	}
	return Swift.max(lhs, rhs)
}
