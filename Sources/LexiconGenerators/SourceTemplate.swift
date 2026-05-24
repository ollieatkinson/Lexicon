//
// github.com/screensailor 2026
//

struct SourceTemplate: Sendable {

	struct Delimiters: Sendable {
		let opening: String
		let closing: String

		static let doubleBraces = Self(opening: "{{", closing: "}}")
		static let percentSigns = Self(opening: "%%", closing: "%%")
	}

	private let template: String
	private let delimiters: Delimiters

	init(_ template: String, delimiters: Delimiters = .doubleBraces) {
		self.template = template
		self.delimiters = delimiters
	}

	func render(_ values: [String: String]) throws -> String {
		var output = template
		for (key, value) in values {
			let placeholder = "\(delimiters.opening)\(key)\(delimiters.closing)"
			output = output.replacingOccurrences(of: placeholder, with: value)
		}
		guard output.range(of: delimiters.opening) == nil else {
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
