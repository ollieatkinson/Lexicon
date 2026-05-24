//
// github.com/screensailor 2022
//

import Lexicon
import Collections

public enum LexiconSourceGenerators {
	
	public static let all: OrderedDictionary<String, LexiconSourceGenerator> = [
		
		"Swift": .init(SwiftLexiconGenerator.self),
		
		"Swift Stand-Alone": .init(SwiftStandAloneGenerator.self),
		
		"Kotlin Stand-Alone": .init(KotlinStandAloneGenerator.self),

		"Go Stand-Alone": .init(GoStandAloneGenerator.self),
		
		"TypeScript Stand-Alone": .init(TypeScriptStandAloneGenerator.self),
		
		"JSON Classes & Mixins": .init(JSONClasses.self),
	]
}

public extension OrderedDictionary where Key == String, Value == LexiconSourceGenerator {

	var commandHelp: String { values.map { $0.command }.joined(separator: ", ") }

	func find(_ command: String) -> LexiconSourceGenerator? {
		first { _, value in value.command == command }?.value
	}
}

public extension Lexicon.Graph.JSON {

	static let generators = LexiconSourceGenerators.all
}
