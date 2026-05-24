//
// github.com/screensailor 2026
//

struct SourceTemplate: Sendable {

	private let template: String

	init(_ template: String) {
		self.template = template
	}

	func render(_ values: [String: String]) throws -> String {
		var output = ""
		var index = template.startIndex

		while let openingRange = template[index...].range(of: "{{") {
			output += template[index..<openingRange.lowerBound]

			let nameStart = openingRange.upperBound
			guard let closingRange = template[nameStart...].range(of: "}}") else {
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
