//
// github.com/screensailor 2026
//

struct SourceTemplate: Sendable {

	private let template: String

	init(_ template: String) {
		self.template = template
	}

	func render(_ values: [String: String]) throws -> String {
		var output = template
		for (key, value) in values {
			output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
		}
		guard output.range(of: "{{") == nil else {
			throw Error.unresolvedPlaceholder(output)
		}
		return output
	}
}

private extension SourceTemplate {

	enum Error: Swift.Error, CustomStringConvertible {
		case unresolvedPlaceholder(String)

		var description: String {
			switch self {
				case .unresolvedPlaceholder(let source):
					return "Unresolved source template placeholder in:\n\(source)"
			}
		}
	}
}
