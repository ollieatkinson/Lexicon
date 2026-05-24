//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
import LexiconGenerators
import UniformTypeIdentifiers

public enum Generator: CodeGenerator {
	public static let utType = TypeScriptStandAloneGenerator.utType
	public static let command = TypeScriptStandAloneGenerator.command

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		try TypeScriptStandAloneGenerator.generate(json)
	}
}
