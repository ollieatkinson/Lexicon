//
// github.com/screensailor 2022
//

import Foundation
import UniformTypeIdentifiers
import Lexicon

public protocol CodeGenerator: Sendable {
	static var utType: UTType { get }
	static var command: String { get }
	static func generate(_ json: Lexicon.Graph.JSON) throws -> Data
}

public protocol SourceCodeGenerator: CodeGenerator {
	static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String
}

public extension SourceCodeGenerator {
	static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		Data(try generateSource(json).utf8)
	}
}
