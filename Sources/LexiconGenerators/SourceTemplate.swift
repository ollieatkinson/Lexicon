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
		var output = ""
		var index = template.startIndex

		while let openingRange = template[index...].range(of: delimiters.opening) {
			output += template[index..<openingRange.lowerBound]

			let nameStart = openingRange.upperBound
			guard let closingRange = template[nameStart...].range(of: delimiters.closing) else {
				output += template[openingRange.lowerBound...]
				return output
			}

			let name = String(template[nameStart..<closingRange.lowerBound])
			guard name.isSourceTemplatePlaceholder else {
				output += template[openingRange.lowerBound..<closingRange.upperBound]
				index = closingRange.upperBound
				continue
			}

			guard let value = values[name] else {
				throw Error.unresolvedPlaceholder(name, template)
			}

			output += value
			index = closingRange.upperBound
		}

		output += template[index...]
		return output
	}
}

private extension SourceTemplate {

	enum Error: Swift.Error, CustomStringConvertible {
		case unresolvedPlaceholder(String, String)

		var description: String {
			switch self {
				case .unresolvedPlaceholder(let name, let source):
					return "Unresolved source template placeholder '\(name)' in:\n\(source)"
			}
		}
	}
}

private extension String {

	var isSourceTemplatePlaceholder: Bool {
		!isEmpty && allSatisfy { character in
			character.isLetter || character.isNumber || character == "_"
		}
	}
}
