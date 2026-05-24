//
// github.com/screensailor 2022
//

import Lexicon
import Collections

public extension Lexicon.Graph.JSON {
	
	static let generators: OrderedDictionary<String, LexiconSourceGenerator> = [
		
		"Swift": .init(SwiftLexiconGenerator.self),
		
		"Swift Stand-Alone": .init(SwiftStandAloneGenerator.self),
		
		"Kotlin Stand-Alone": .init(KotlinStandAloneGenerator.self),

		"Go Stand-Alone": .init(GoStandAloneGenerator.self),
		
		"TypeScript Stand-Alone": .init(TypeScriptStandAloneGenerator.self),
		
		"JSON Classes & Mixins": .init(JSONClasses.self),
	]
}
