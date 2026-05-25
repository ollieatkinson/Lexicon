//
// github.com/screensailor 2026
//

import Lexicon

extension String {

	var standAloneTypeSuffix: String {
		replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "_&_", with: "_")
	}

	func standAloneProtocolInheritanceSuffix(protocolPrefix: String) -> String {
		replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "__&__", with: ", \(protocolPrefix)_")
	}
}

struct StandAloneTypeNames: Sendable {
	var id: String
	var classPrefix: String
	var protocolPrefix: String

	init(id: String, prefix: (class: String, protocol: String)) {
		self.id = id
		self.classPrefix = prefix.class
		self.protocolPrefix = prefix.protocol
	}

	var className: String { className(for: id) }
	var protocolName: String { protocolName(for: id) }

	func className(for id: String) -> String {
		"\(classPrefix)_\(id.standAloneTypeSuffix)"
	}

	func protocolName(for id: String) -> String {
		"\(protocolPrefix)_\(id.standAloneTypeSuffix)"
	}

	func protocolBase(supertype: String?) -> String {
		"\(protocolPrefix)\(supertype.map { "_\($0.standAloneProtocolInheritanceSuffix(protocolPrefix: protocolPrefix))" } ?? "")"
	}
}

struct StandAloneAccessor: Sendable {
	var name: String
	var sourceID: String
	var targetID: String
	var pathSuffix: String
	var isSynonym: Bool
}

extension Lexicon.Graph.Node.Class.JSON {

	func standAloneAccessors() -> [StandAloneAccessor] {
		var accessors: [StandAloneAccessor] = []

		for child in children ?? [] {
			let id = "\(id).\(child)"
			accessors.append(.init(
				name: child,
				sourceID: id,
				targetID: id,
				pathSuffix: child,
				isSynonym: false
			))
		}

		for (synonym, protonym) in (synonyms?.sorted(by: { $0.key < $1.key }) ?? []) {
			accessors.append(.init(
				name: synonym,
				sourceID: "\(id).\(synonym)",
				targetID: "\(id).\(protonym)",
				pathSuffix: protonym,
				isSynonym: true
			))
		}

		return accessors
	}

	func standAloneTypeAccessors(classes: [Lexicon.Graph.Node.Class.JSON]) -> [StandAloneAccessor] {
		(type ?? []).flatMap { typeID in
			classes.first { $0.id == typeID }?.standAloneAccessors() ?? []
		}
	}

	func standAloneAllAccessors(classes: [Lexicon.Graph.Node.Class.JSON]) -> [StandAloneAccessor] {
		var accessors = Dictionary(
			uniqueKeysWithValues: standAloneInheritedAccessors(classes: classes).map { ($0.name, $0) }
		)
		for accessor in standAloneAccessors() {
			accessors[accessor.name] = accessor
		}
		return accessors.values.sorted { $0.name < $1.name }
	}

	func standAloneInheritedAccessors(classes: [Lexicon.Graph.Node.Class.JSON]) -> [StandAloneAccessor] {
		guard let supertype else {
			return []
		}
		guard let type = classes.first(where: { $0.id == supertype }) else {
			return []
		}
		guard let mixin = type.mixin else {
			return type.standAloneAllAccessors(classes: classes)
		}

		var accessors = Dictionary(
			uniqueKeysWithValues: type.standAloneInheritedAccessors(classes: classes).map { ($0.name, $0) }
		)
		for (name, id) in mixin.children ?? [:] {
			accessors[name] = .init(
				name: name,
				sourceID: id,
				targetID: id,
				pathSuffix: name,
				isSynonym: false
			)
		}
		return accessors.values.sorted { $0.name < $1.name }
	}
}
