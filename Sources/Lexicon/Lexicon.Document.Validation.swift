//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon {

	struct SourcePosition: Hashable, Comparable, Sendable {
		public var line: Int
		public var utf16Column: Int
		public var utf16Offset: Int

		public init(line: Int, utf16Column: Int, utf16Offset: Int) {
			self.line = line
			self.utf16Column = utf16Column
			self.utf16Offset = utf16Offset
		}

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.utf16Offset < rhs.utf16Offset
		}
	}

	struct SourceRange: Hashable, Sendable {
		public var lowerBound: SourcePosition
		public var upperBound: SourcePosition

		public init(lowerBound: SourcePosition, upperBound: SourcePosition) {
			self.lowerBound = lowerBound
			self.upperBound = upperBound
		}

		public var utf16Offsets: Range<Int> {
			lowerBound.utf16Offset..<upperBound.utf16Offset
		}
	}

	struct Diagnostic: Hashable, Sendable, CustomStringConvertible {
		public enum Severity: String, Hashable, Sendable {
			case error
			case warning
		}

		public enum Code: String, Hashable, Sendable {
			case invalidName
			case missingRoot
			case duplicateRoot
			case duplicateChild
			case duplicateType
			case duplicateImport
			case duplicateConnection
			case duplicateProtonym
			case duplicateDefault
			case leadingSpaces
			case indentationJump
			case misplacedMetadata
			case unknownLine
			case invalidReference
			case unresolvedType
			case unresolvedProtonym
			case unresolvedDefault
			case synonymHasChildren
			case synonymHasTypes
			case synonymTypeTarget
			case typeCycle
			case protonymCycle
			case mixedResolutionCycle
		}

		public var severity: Severity
		public var code: Code
		public var message: String
		public var path: Lemma.ID?
		public var reference: String?
		public var cycle: [Lemma.ID]
		public var sourceRange: SourceRange?

		public init(
			severity: Severity = .error,
			code: Code,
			message: String,
			path: Lemma.ID? = nil,
			reference: String? = nil,
			cycle: [Lemma.ID] = [],
			sourceRange: SourceRange? = nil
		) {
			self.severity = severity
			self.code = code
			self.message = message
			self.path = path
			self.reference = reference
			self.cycle = cycle
			self.sourceRange = sourceRange
		}

		public var description: String {
			var prefix = code.rawValue
			if let path {
				prefix += " at \(path)"
			}
			return "\(prefix): \(message)"
		}
	}

	struct ValidationError: Error, Hashable, Sendable, CustomStringConvertible,
		LocalizedError {

		public var diagnostics: [Diagnostic]

		public init(diagnostics: [Diagnostic]) {
			self.diagnostics = diagnostics
		}

		public var description: String {
			diagnostics.map(\.description).joined(separator: "\n")
		}

		public var errorDescription: String? {
			description
		}
	}
}

public extension Lexicon.Document {

	func validate() -> [Lexicon.Diagnostic] {
		var diagnostics: [Lexicon.Diagnostic] = []
		guard roots.isNotEmpty else {
			return [
				.init(
					code: .missingRoot,
					message: "The document must declare at least one root lemma"
				)
			]
		}

		let generation = Lexicon.Generation(
			lexiconID: .init(),
			revision: .initial,
			document: self
		)
		var edges: [Lemma.ID: [DependencyEdge]] = [:]

		for id in generation.rawNodes.keys.sorted() {
			guard let node = generation.rawNodes[id] else {
				continue
			}
			edges[id, default: []] = []

			if node.protonym != nil {
				if node.children.isNotEmpty {
					diagnostics.append(.init(
						code: .synonymHasChildren,
						message: "A synonym cannot declare children",
						path: id
					))
				}
				if node.type.isNotEmpty {
					diagnostics.append(.init(
						code: .synonymHasTypes,
						message: "A synonym cannot declare type references",
						path: id
					))
				}
			}

			for type in node.type.sorted() {
				guard let target = generation.rawNodes[type] else {
					diagnostics.append(.init(
						code: .unresolvedType,
						message: "Type reference '\(type)' does not resolve to a declared lemma",
						path: id,
						reference: type.description
					))
					continue
				}
				if target.protonym != nil {
					diagnostics.append(.init(
						code: .synonymTypeTarget,
						message: "Type reference '\(type)' targets a synonym",
						path: id,
						reference: type.description
					))
				}
				edges[id, default: []].append(.init(to: type, kind: .type))
			}

			if let protonym = node.protonym {
				guard let parent = id.parent else {
					diagnostics.append(.init(
						code: .unresolvedProtonym,
						message: "A root lemma cannot be a synonym",
						path: id,
						reference: protonym.description
					))
					continue
				}
				let targetID = parent.appending(protonym)
				guard let target = generation.resolve(targetID) else {
					diagnostics.append(.init(
						code: .unresolvedProtonym,
						message: "Protonym '\(protonym)' does not resolve from '\(parent)'",
						path: id,
						reference: protonym.description
					))
					continue
				}
				edges[id, default: []].append(.init(to: target.nodeID, kind: .protonym))
			}

			if case .reference(let reference) = node.defaultValue,
				generation.resolve(reference) == nil
			{
				diagnostics.append(.init(
					code: .unresolvedDefault,
					message: "Default reference '\(reference)' does not resolve",
					path: id,
					reference: reference.description
				))
			}
		}

		diagnostics.append(contentsOf: Self.cycleDiagnostics(edges: edges))
		return diagnostics.sorted {
			(
				$0.path?.description ?? "",
				$0.code.rawValue,
				$0.reference ?? "",
				$0.message
			) < (
				$1.path?.description ?? "",
				$1.code.rawValue,
				$1.reference ?? "",
				$1.message
			)
		}
	}

	func validated() throws -> Self {
		let diagnostics = validate().filter { $0.severity == .error }
		guard diagnostics.isEmpty else {
			throw Lexicon.ValidationError(diagnostics: diagnostics)
		}
		return self
	}
}

private extension Lexicon.Document {

	enum DependencyKind: String, Hashable {
		case type
		case protonym
	}

	struct DependencyEdge: Hashable {
		var to: Lemma.ID
		var kind: DependencyKind
	}

	static func cycleDiagnostics(
		edges: [Lemma.ID: [DependencyEdge]]
	) -> [Lexicon.Diagnostic] {
		let components = stronglyConnectedComponents(edges: edges)
		var diagnostics: [Lexicon.Diagnostic] = []

		for component in components {
			let members = Set(component)
			let containsSelfEdge = component.count == 1 && edges[component[0], default: []]
				.contains { $0.to == component[0] }
			guard component.count > 1 || containsSelfEdge else {
				continue
			}
			let searches: [
				(
					code: Lexicon.Diagnostic.Code,
					allowed: Set<DependencyKind>,
					required: Set<DependencyKind>
				)
			] = [
				(.typeCycle, [.type], [.type]),
				(.protonymCycle, [.protonym], [.protonym]),
				(.mixedResolutionCycle, [.type, .protonym], [.type, .protonym]),
			]
			for search in searches {
				guard
					let cycle = canonicalCycle(
						in: members,
						edges: edges,
						allowedKinds: search.allowed,
						requiredKinds: search.required
					)
				else {
					continue
				}
				let rendered = cycle.ids.map(\.description).joined(separator: " -> ")
				diagnostics.append(.init(
					code: search.code,
					message: "Resolution cycle: \(rendered)",
					path: cycle.ids.first,
					cycle: cycle.ids
				))
			}
		}
		return diagnostics
	}

	static func stronglyConnectedComponents(
		edges: [Lemma.ID: [DependencyEdge]]
	) -> [[Lemma.ID]] {
		var index = 0
		var indexes: [Lemma.ID: Int] = [:]
		var lowLinks: [Lemma.ID: Int] = [:]
		var stack: [Lemma.ID] = []
		var onStack: Set<Lemma.ID> = []
		var result: [[Lemma.ID]] = []

		func visit(_ vertex: Lemma.ID) {
			indexes[vertex] = index
			lowLinks[vertex] = index
			index += 1
			stack.append(vertex)
			onStack.insert(vertex)

			for edge in edges[vertex, default: []].sorted(by: {
				($0.to, $0.kind.rawValue) < ($1.to, $1.kind.rawValue)
			}) where edges[edge.to] != nil {
				if indexes[edge.to] == nil {
					visit(edge.to)
					lowLinks[vertex] = min(lowLinks[vertex]!, lowLinks[edge.to]!)
				} else if onStack.contains(edge.to) {
					lowLinks[vertex] = min(lowLinks[vertex]!, indexes[edge.to]!)
				}
			}

			if lowLinks[vertex] == indexes[vertex] {
				var component: [Lemma.ID] = []
				while let last = stack.popLast() {
					onStack.remove(last)
					component.append(last)
					if last == vertex {
						break
					}
				}
				result.append(component.sorted())
			}
		}

		for vertex in edges.keys.sorted() where indexes[vertex] == nil {
			visit(vertex)
		}
		return result.sorted {
			($0.first?.description ?? "") < ($1.first?.description ?? "")
		}
	}

	static func canonicalCycle(
		in members: Set<Lemma.ID>,
		edges: [Lemma.ID: [DependencyEdge]],
		allowedKinds: Set<DependencyKind>,
		requiredKinds: Set<DependencyKind>
	) -> (ids: [Lemma.ID], kinds: [DependencyKind])? {
		struct SearchState: Hashable {
			var vertex: Lemma.ID
			var kinds: Set<DependencyKind>
		}

		struct SearchPath {
			var state: SearchState
			var ids: [Lemma.ID]
			var kinds: [DependencyKind]
		}

		for start in members.sorted() {
			let initial = SearchState(vertex: start, kinds: [])
			var visited: Set<SearchState> = [initial]
			var queue = [SearchPath(state: initial, ids: [start], kinds: [])]
			var index = 0

			while index < queue.count {
				let path = queue[index]
				index += 1
				for edge in edges[path.state.vertex, default: []]
					.filter({
						members.contains($0.to) && allowedKinds.contains($0.kind)
					})
					.sorted(by: {
						($0.to, $0.kind.rawValue) < ($1.to, $1.kind.rawValue)
					})
				{
					let kinds = path.state.kinds.union([edge.kind])
					let ids = path.ids + [edge.to]
					let edgeKinds = path.kinds + [edge.kind]
					if edge.to == start, kinds.isSuperset(of: requiredKinds) {
						return (ids, edgeKinds)
					}
					let state = SearchState(vertex: edge.to, kinds: kinds)
					guard visited.insert(state).inserted else {
						continue
					}
					queue.append(.init(
						state: state,
						ids: ids,
						kinds: edgeKinds
					))
				}
			}
		}
		return nil
	}
}
