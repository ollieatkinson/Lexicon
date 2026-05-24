//
// github.com/screensailor 2022
//

import Lexicon
import Collections
import SwiftLexicon

public extension Lexicon.Graph.JSON {
	
	static let generators: OrderedDictionary<String, LexiconSourceGenerator> = [
		
		"Swift": .init(SwiftLexicon.Generator.self),
		
		"Swift Stand-Alone": .init(SwiftStandAloneGenerator.self),
		
		"Kotlin Stand-Alone": .init(KotlinStandAloneGenerator.self),
		
		"TypeScript Stand-Alone": .init(TypeScriptStandAloneGenerator.self),
		
		"JSON Classes & Mixins": .init(JSONClasses.self),
	]
}
