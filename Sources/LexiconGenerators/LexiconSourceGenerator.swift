//
// github.com/screensailor 2026
//

import Foundation
import Lexicon
import UniformTypeIdentifiers

public struct LexiconSourceGenerator: Sendable {

	public var command: String
	public var utType: UTType
	private var generator: @Sendable (Lexicon.Graph.JSON) throws -> Data

	public init(
		command: String,
		utType: UTType,
		generate: @escaping @Sendable (Lexicon.Graph.JSON) throws -> Data
	) {
		self.command = command
		self.utType = utType
		self.generator = generate
	}

	public init(_ type: CodeGenerator.Type) {
		self.init(
			command: type.command,
			utType: type.utType,
			generate: type.generate
		)
	}

	public func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		try generator(json)
	}
}
