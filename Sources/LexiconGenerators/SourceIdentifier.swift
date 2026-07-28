//
// github.com/screensailor 2026
//

import Lexicon

extension String {

	var standAloneTypeSuffix: String {
		replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
	}
}

public struct StandAloneTypePrefixes: Sendable, Equatable {
	public var classPrefix: String
	public var protocolPrefix: String

	public init(class classPrefix: String = "L", protocol protocolPrefix: String = "I") {
		self.classPrefix = classPrefix
		self.protocolPrefix = protocolPrefix
	}

	public static let `default` = StandAloneTypePrefixes()
}

public enum StandAloneGenerationError: Error, Equatable, Sendable, CustomStringConvertible {
	case invalidTypePrefix(kind: String, value: String)
	case invalidAccessorName(owner: Lemma.ID, value: String)
	case duplicateClass(Lemma.ID)
	case missingClass(id: Lemma.ID, referencedBy: Lemma.ID)
	case inheritanceCycle(Lemma.ID)
	case protonymCycle(Lemma.ID)
	case memberCollision(owner: Lemma.ID, name: Lemma.Name)
	case reservedMember(language: String, owner: Lemma.ID, name: Lemma.Name)
	case reservedRoot(language: String, name: Lemma.Name)
	case symbolCollision(symbol: String, first: String, second: String)

	public var description: String {
		switch self {
		case .invalidTypePrefix(let kind, let value):
			"'\(value)' is not a valid \(kind) type prefix."
		case .invalidAccessorName(let owner, let value):
			"'\(value)' is not a valid accessor name in '\(owner)'."
		case .duplicateClass(let id):
			"Graph JSON declares class '\(id)' more than once."
		case .missingClass(let id, let owner):
			"Class '\(owner)' references missing class '\(id)'."
		case .inheritanceCycle(let id):
			"Class inheritance contains a cycle at '\(id)'."
		case .protonymCycle(let id):
			"Class protonyms contain a cycle at '\(id)'."
		case .memberCollision(let owner, let name):
			"Class '\(owner)' declares more than one member named '\(name)'."
		case .reservedMember(let language, let owner, let name):
			"\(language) reserves member '\(name)' in generated class '\(owner)'."
		case .reservedRoot(let language, let name):
			"\(language) root '\(name)' conflicts with a generated scaffold declaration."
		case .symbolCollision(let symbol, let first, let second):
			"Generated symbol '\(symbol)' collides between \(first) and \(second)."
		}
	}

}

struct StandAloneTypeNames: Sendable {
	var id: Lemma.ID
	var prefixes: StandAloneTypePrefixes
	var baseClassName: String
	var baseProtocolName: String

	init(id: Lemma.ID, prefix: (class: String, protocol: String)) {
		self.init(id: id, prefixes: .init(class: prefix.class, protocol: prefix.protocol))
	}

	init(
		id: Lemma.ID,
		prefixes: StandAloneTypePrefixes,
		baseClassName: String = "L",
		baseProtocolName: String = "I"
	) {
		self.id = id
		self.prefixes = prefixes
		self.baseClassName = baseClassName
		self.baseProtocolName = baseProtocolName
	}

	var classPrefix: String { prefixes.classPrefix }
	var protocolPrefix: String { prefixes.protocolPrefix }
	var className: String { className(for: id) }
	var protocolName: String { protocolName(for: id) }

	func className(for id: Lemma.ID) -> String {
		"\(classPrefix)_\(id.description.standAloneTypeSuffix)"
	}

	func protocolName(for id: Lemma.ID) -> String {
		"\(protocolPrefix)_\(id.description.standAloneTypeSuffix)"
	}

	func protocolBase(
		supertype: Lemma.ID?,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> String {
		guard let supertype else {
			return baseProtocolName
		}
		return try classes
			.standAloneProtocolTypes(for: supertype, referencedBy: id)
			.map(protocolName)
			.joined(separator: ", ")
	}
}

extension Lexicon.Graph.JSON {

	func validateStandAloneSymbols(prefixes: StandAloneTypePrefixes) throws {
		guard prefixes.classPrefix.isSourceIdentifierPrefix else {
			throw StandAloneGenerationError.invalidTypePrefix(
				kind: "class",
				value: prefixes.classPrefix
			)
		}
		guard prefixes.protocolPrefix.isSourceIdentifierPrefix else {
			throw StandAloneGenerationError.invalidTypePrefix(
				kind: "protocol",
				value: prefixes.protocolPrefix
			)
		}
		for type in classes {
			_ = try type.standAloneDeclaredAccessors()
		}
		let rootID = Lemma.ID(root: name)
		guard classes.contains(where: { $0.id == rootID }) else {
			throw StandAloneGenerationError.missingClass(
				id: rootID,
				referencedBy: rootID
			)
		}
		try classes.validateStandAloneClassGraph()

		var symbols: [String: String] = [:]
		func insert(_ symbol: String, declaration: String) throws {
			if let existing = symbols[symbol] {
				throw StandAloneGenerationError.symbolCollision(
					symbol: symbol,
					first: existing,
					second: declaration
				)
			}
			symbols[symbol] = declaration
		}

		try insert("L", declaration: "base class")
		try insert("I", declaration: "base protocol")
		try insert(name.rawValue, declaration: "root binding '\(name)'")

		for type in classes where type.mixin == nil {
			let names = StandAloneTypeNames(id: type.id, prefixes: prefixes)
			try insert(names.className, declaration: "class '\(type.id)'")
			if type.protonym == nil {
				try insert(names.protocolName, declaration: "protocol '\(type.id)'")
			}
			_ = try names.protocolBase(supertype: type.supertype, classes: classes)
		}
	}

	func validateStandAloneMembers(
		language: String,
		reserved: Set<String>
	) throws {
		for type in classes where type.mixin == nil {
			for accessor in try type.standAloneGeneratedAccessors(classes: classes)
			where reserved.contains(accessor.name.rawValue) {
				throw StandAloneGenerationError.reservedMember(
					language: language,
					owner: type.id,
					name: accessor.name
				)
			}
		}
	}

	func validateStandAloneRoot(
		language: String,
		reserved: Set<String>
	) throws {
		guard !reserved.contains(name.rawValue) else {
			throw StandAloneGenerationError.reservedRoot(
				language: language,
				name: name
			)
		}
	}
}

extension String {
	var isSourceIdentifierPrefix: Bool {
		guard let first else {
			return false
		}
		guard first == "_" || first.isLetter else {
			return false
		}
		return dropFirst().allSatisfy { character in
			character == "_" || character.isLetter || character.isNumber
		}
	}

	var swiftDeclarationIdentifier: String {
		swiftKeywords.contains(self) ? "`\(self)`" : self
	}

	var kotlinDeclarationIdentifier: String {
		kotlinKeywords.contains(self) ? "`\(self)`" : self
	}

	var isTypeScriptBindingKeyword: Bool {
		typeScriptBindingKeywords.contains(self)
	}
}

extension Lemma.RelativeID {
	var swiftMemberPath: String {
		components
			.map { $0.rawValue.swiftDeclarationIdentifier }
			.joined(separator: ".")
	}

	var kotlinMemberPath: String {
		components
			.map { $0.rawValue.kotlinDeclarationIdentifier }
			.joined(separator: ".")
	}
}

private let swiftKeywords: Set<String> = [
	"Any", "Self", "actor", "any", "as", "associatedtype", "borrowing", "break",
	"case", "catch", "class", "consuming", "continue", "default", "defer", "deinit",
	"do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for",
	"func", "guard", "if", "import", "in", "indirect", "init", "inout", "internal",
	"is", "isolated", "let", "macro", "nil", "nonisolated", "open", "operator",
	"package", "precedencegroup", "private", "protocol", "public", "repeat", "rethrows",
	"return", "self", "sending", "some", "static", "struct", "subscript", "super",
	"switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
]

private let kotlinKeywords: Set<String> = [
	"as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if",
	"in", "interface", "is", "null", "object", "package", "return", "super", "this",
	"throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while",
]

private let typeScriptBindingKeywords: Set<String> = [
	"arguments", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
	"default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
	"eval", "for", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new",
	"null", "package", "private", "protected", "public", "return", "static", "super",
	"switch", "this", "throw", "true", "try", "typeof", "var", "void", "while", "with",
	"yield",
]

struct StandAloneAccessor: Sendable {
	var name: Lemma.Name
	var sourceID: Lemma.ID
	var targetID: Lemma.ID
	var pathSuffix: Lemma.RelativeID
	var isSynonym: Bool
}

private extension StandAloneAccessor {

	func resolvingProtonym(
		classes: [Lexicon.Graph.Node.Class.JSON],
		declaredBy owner: Lemma.ID
	) throws -> Self {
		guard classes.contains(where: { $0.id == targetID }) else {
			return self
		}
		let canonicalID = try classes.standAloneCanonicalID(
			for: targetID,
			referencedBy: sourceID
		)
		guard canonicalID != targetID else {
			return self
		}
		var result = self
		result.targetID = canonicalID
		if isSynonym {
			result.pathSuffix = try canonicalID.relative(to: owner)
		}
		return result
	}
}

extension Lexicon.Graph.Node.Class.JSON {

	func standAloneAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [StandAloneAccessor] {
		try standAloneDeclaredAccessors().map { accessor in
			try accessor.resolvingProtonym(classes: classes, declaredBy: id)
		}
	}

	fileprivate func standAloneDeclaredAccessors() throws -> [StandAloneAccessor] {
		var accessors: [StandAloneAccessor] = []
		var names: Set<Lemma.Name> = []

		for child in children ?? [] {
			guard names.insert(child).inserted else {
				throw StandAloneGenerationError.memberCollision(owner: id, name: child)
			}
			let childID = id.appending(child)
			accessors.append(.init(
				name: child,
				sourceID: childID,
				targetID: childID,
				pathSuffix: try Lemma.RelativeID(components: [child]),
				isSynonym: false
			))
		}

		for (synonym, protonym) in (synonyms?.sorted(by: { $0.key < $1.key }) ?? []) {
			let synonymName: Lemma.Name
			do {
				synonymName = try Lemma.Name(validating: synonym)
			} catch {
				throw StandAloneGenerationError.invalidAccessorName(owner: id, value: synonym)
			}
			guard names.insert(synonymName).inserted else {
				throw StandAloneGenerationError.memberCollision(owner: id, name: synonymName)
			}
			accessors.append(.init(
				name: synonymName,
				sourceID: id.appending(synonymName),
				targetID: id.appending(protonym),
				pathSuffix: protonym,
				isSynonym: true
			))
		}

		return accessors
	}

	func standAloneTypeAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [StandAloneAccessor] {
		try (type ?? []).flatMap { typeID in
			let canonicalTypeID = try classes.standAloneCanonicalID(
				for: typeID,
				referencedBy: id
			)
			guard let type = classes.first(where: { $0.id == canonicalTypeID }) else {
				throw StandAloneGenerationError.missingClass(
					id: canonicalTypeID,
					referencedBy: id
				)
			}
			return try type.standAloneAccessors(classes: classes)
		}
	}

	func standAloneGeneratedAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [StandAloneAccessor] {
		var accessors = try standAloneTypeAccessors(classes: classes)
		accessors.append(contentsOf: try standAloneInheritedAccessors(classes: classes))
		accessors.append(contentsOf: try standAloneAccessors(classes: classes))
		return accessors
	}

	func standAloneAllAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [StandAloneAccessor] {
		var accessors: [Lemma.Name: StandAloneAccessor] = [:]
		for accessor in try standAloneInheritedAccessors(classes: classes) {
			accessors[accessor.name] = accessor
		}
		for accessor in try standAloneAccessors(classes: classes) {
			accessors[accessor.name] = accessor
		}
		return accessors.values.sorted { $0.name < $1.name }
	}

	func standAloneInheritedAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [StandAloneAccessor] {
		var visiting: Set<Lemma.ID> = []
		return try standAloneInheritedAccessors(classes: classes, visiting: &visiting)
	}

	private func standAloneInheritedAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON],
		visiting: inout Set<Lemma.ID>
	) throws -> [StandAloneAccessor] {
		guard let supertype else {
			return []
		}
		let canonicalSupertype = try classes.standAloneCanonicalID(
			for: supertype,
			referencedBy: id
		)
		guard visiting.insert(canonicalSupertype).inserted else {
			throw StandAloneGenerationError.inheritanceCycle(canonicalSupertype)
		}
		defer { visiting.remove(canonicalSupertype) }
		guard let type = classes.first(where: { $0.id == canonicalSupertype }) else {
			throw StandAloneGenerationError.missingClass(
				id: canonicalSupertype,
				referencedBy: id
			)
		}
		guard let mixin = type.mixin else {
			var inherited = try type.standAloneInheritedAccessors(
				classes: classes,
				visiting: &visiting
			)
			for accessor in try type.standAloneAccessors(classes: classes) {
				if let index = inherited.firstIndex(where: { $0.name == accessor.name }) {
					inherited[index] = accessor
				} else {
					inherited.append(accessor)
				}
			}
			return inherited.sorted { $0.name < $1.name }
		}

		var accessors: [Lemma.Name: StandAloneAccessor] = [:]
		for accessor in try type.standAloneInheritedAccessors(
			classes: classes,
			visiting: &visiting
		) {
			accessors[accessor.name] = accessor
		}
		for (name, id) in mixin.children ?? [:] {
			let memberName: Lemma.Name
			do {
				memberName = try Lemma.Name(validating: name)
			} catch {
				throw StandAloneGenerationError.invalidAccessorName(owner: type.id, value: name)
			}
			let accessor = StandAloneAccessor(
				name: memberName,
				sourceID: id,
				targetID: id,
				pathSuffix: try Lemma.RelativeID(components: [memberName]),
				isSynonym: false
			)
			accessors[memberName] = try accessor.resolvingProtonym(
				classes: classes,
				declaredBy: type.id
			)
		}
		return accessors.values.sorted { $0.name < $1.name }
	}
}

extension Array where Element == Lexicon.Graph.Node.Class.JSON {

	func validateStandAloneClassGraph() throws {
		var classIDs: Set<Lemma.ID> = []
		for type in self {
			guard classIDs.insert(type.id).inserted else {
				throw StandAloneGenerationError.duplicateClass(type.id)
			}
			if let children = type.mixin?.children {
				for name in children.values.keys {
					guard (try? Lemma.Name(validating: name)) != nil else {
						throw StandAloneGenerationError.invalidAccessorName(
							owner: type.id,
							value: name
						)
					}
				}
			}
		}
		for type in self {
			for reference in type.standAloneRequiredClassIDs() where !classIDs.contains(reference) {
				throw StandAloneGenerationError.missingClass(
					id: reference,
					referencedBy: type.id
				)
			}
		}
		for type in self where type.protonym != nil {
			_ = try standAloneCanonicalID(for: type.id, referencedBy: type.id)
		}

		var visited: Set<Lemma.ID> = []
		var visiting: Set<Lemma.ID> = []
		func visit(_ id: Lemma.ID) throws {
			guard !visited.contains(id) else {
				return
			}
			guard visiting.insert(id).inserted else {
				throw StandAloneGenerationError.inheritanceCycle(id)
			}
			defer { visiting.remove(id) }
			guard let type = first(where: { $0.id == id }) else {
				return
			}
			if let supertype = type.supertype {
				try visit(supertype)
			}
			visited.insert(id)
		}
		for type in self {
			try visit(type.id)
		}
	}

	func standAloneCanonicalID(
		for id: Lemma.ID,
		referencedBy owner: Lemma.ID
	) throws -> Lemma.ID {
		var current = id
		var visiting: Set<Lemma.ID> = []
		while true {
			guard visiting.insert(current).inserted else {
				throw StandAloneGenerationError.protonymCycle(current)
			}
			guard let type = first(where: { $0.id == current }) else {
				throw StandAloneGenerationError.missingClass(
					id: current,
					referencedBy: owner
				)
			}
			guard let protonym = type.protonym else {
				return current
			}
			current = protonym
		}
	}

	func standAloneProtocolTypes(
		for id: Lemma.ID,
		referencedBy owner: Lemma.ID
	) throws -> [Lemma.ID] {
		var visiting: Set<Lemma.ID> = []
		var result: [Lemma.ID] = []
		try appendStandAloneProtocolTypes(
			for: id,
			referencedBy: owner,
			visiting: &visiting,
			to: &result
		)
		return result
	}

	func appendStandAloneProtocolTypes(
		for id: Lemma.ID,
		referencedBy owner: Lemma.ID,
		visiting: inout Set<Lemma.ID>,
		to result: inout [Lemma.ID]
	) throws {
		let canonicalID = try standAloneCanonicalID(for: id, referencedBy: owner)
		guard visiting.insert(canonicalID).inserted else {
			throw StandAloneGenerationError.inheritanceCycle(canonicalID)
		}
		defer { visiting.remove(canonicalID) }
		guard let type = first(where: { $0.id == canonicalID }) else {
			throw StandAloneGenerationError.missingClass(id: canonicalID, referencedBy: owner)
		}
		guard let mixin = type.mixin else {
			if !result.contains(canonicalID) {
				result.append(canonicalID)
			}
			return
		}
		if let supertype = type.supertype {
			try appendStandAloneProtocolTypes(
				for: supertype,
				referencedBy: owner,
				visiting: &visiting,
				to: &result
			)
		}
		try appendStandAloneProtocolTypes(
			for: mixin.type,
			referencedBy: owner,
			visiting: &visiting,
			to: &result
		)
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func standAloneRequiredClassIDs() -> Set<Lemma.ID> {
		var result = Set(type ?? [])
		if let protonym {
			result.insert(protonym)
		}
		if let supertype {
			result.insert(supertype)
		}
		for child in children ?? [] {
			result.insert(id.appending(child))
		}
		for (name, relativeID) in synonyms ?? [:] {
			if let name = try? Lemma.Name(validating: name) {
				result.insert(id.appending(name))
			}
			result.insert(id.appending(relativeID))
		}
		if let mixin {
			result.insert(mixin.type)
			if let children = mixin.children {
				result.formUnion(children.values.values)
			}
		}
		return result
	}
}
