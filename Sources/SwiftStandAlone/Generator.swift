//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
import LexiconGenerators
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum Generator: CodeGenerator {
	public static let utType = SwiftStandAloneGenerator.utType
	public static let command = SwiftStandAloneGenerator.command

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		try SwiftStandAloneGenerator.generate(json)
	}
}
