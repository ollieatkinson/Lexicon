//
// github.com/screensailor 2026
//

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
