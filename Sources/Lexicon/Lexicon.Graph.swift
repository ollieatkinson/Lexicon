//
// github.com/screensailor 2021
//

import Foundation

public extension Lexicon {

	struct Graph: Sendable {

		public var date: Date
		public var root: Node

		public init(name: Lemma.Name = "root", date: Date = .init()) {
			self.date = date
			self.root = Node(name: name)
		}

		public init(root: Node, date: Date = .init()) {
			self.date = date
			self.root = root
		}
	}
}

public extension Lexicon.Graph {

	typealias Path = WritableKeyPath<Node, Node>

	subscript(_ node: Path) -> Node {
		get {
			return root[keyPath: node]
		}
		set {
			root[keyPath: node] = newValue
		}
	}
}

extension Lexicon.Graph: Equatable {

	public static func == (lhs: Lexicon.Graph, rhs: Lexicon.Graph) -> Bool {
		lhs.date == rhs.date &&
		lhs.root == rhs.root
	}
}

extension Lexicon.Graph: CustomStringConvertible {

	public var description: String {
		"\(Self.self)(root: \(root.name), date: \(date)"
	}
}

#if canImport(NaturalLanguage)
import NaturalLanguage

public extension Lexicon.Graph {

	static let underscore = CharacterSet(charactersIn: "_")
	static let specialSentenceTerminator = CharacterSet(charactersIn: ";–()[]{}")

	static func from(sentences string: String, root name: Lemma.Name = "a") -> Lexicon.Graph {

		var root = Node(name: name)

		root.make(child: "word")
		root.make(child: "sentence")

		let word: WritableKeyPath<Node, Node> = \.["word"]
		let sentence: WritableKeyPath<Node, Node> = \.["sentence"]

		let tagger = NLTagger(tagSchemes: [.lexicalClass])
		let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
		let sentences = NLTokenizer(unit: .sentence)
		sentences.string = string

		sentences.enumerateTokens(in: string.indices.range) { range, _ in

			var node = sentence

			for sentence in string[range].components(separatedBy: specialSentenceTerminator) {

				tagger.string = sentence

				tagger.enumerateTags(in: sentence.indices.range, unit: .word, scheme: .lexicalClass, options: options) { tag, range in

					guard let token = tag?.rawValue.lowercased() else {
						return true
					}

					var string = sentence[range].lowercased().trimmingCharacters(in: underscore).filter{ character in
						CharacterSet(charactersIn: String(character)).isSubset(of: Lemma.validCharacterOfName)
					}

					guard let first = string.first else {
						return true
					}

					if first.isNumber {
						string = "_\(string)"
					}

					root[keyPath: node].make(child: string)
					node = node.appending(path: \.[string])

					let type = root[keyPath: word].make(child: token)

					root[keyPath: node].type.insert("\(root.name).word.\(type.name)")

					return true
				}
			}
			return true
		}
		return Lexicon.Graph(root: root)
	}
}
#else
public extension Lexicon.Graph {

	static func from(sentences string: String, root name: Lemma.Name = "a") -> Lexicon.Graph {

		var root = Node(name: name)

		root.make(child: "word")
		root.make(child: "sentence")

		let word: WritableKeyPath<Node, Node> = \.["word"]
		let sentence: WritableKeyPath<Node, Node> = \.["sentence"]

		for sentenceString in string.components(separatedBy: sentenceSeparators) {
			var node = sentence

			for string in Self.words(in: sentenceString) {
				root[keyPath: node].make(child: string)
				node = node.appending(path: \.[string])

				let type = root[keyPath: word].make(child: Self.lexicalClass(for: string))

				root[keyPath: node].type.insert("\(root.name).word.\(type.name)")
			}
		}
		return Lexicon.Graph(root: root)
	}
}

private extension Lexicon.Graph {

	static let sentenceSeparators = CharacterSet.newlines.union(CharacterSet(charactersIn: ".!?;–()[]{}"))

	static func words(in sentence: String) -> [String] {
		sentence
			.replacingOccurrences(of: "n't", with: " nt", options: .caseInsensitive)
			.replacingOccurrences(of: "n’t", with: " nt", options: .caseInsensitive)
			.components(separatedBy: Lemma.validCharacterOfName.inverted)
			.compactMap { word -> String? in
				var word = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "_"))
				guard let first = word.first else {
					return nil
				}
				if first.isNumber {
					word = "_\(word)"
				}
				return word
			}
	}

	static func lexicalClass(for word: String) -> String {
		if word.first == "_", word.dropFirst().allSatisfy(\.isNumber) {
			return "number"
		}
		switch word {
			case "a", "an", "the":
				return "determiner"
			case "all", "again", "nt", "together":
				return "adverb"
			case "and", "or":
				return "conjunction"
			case "great":
				return "adjective"
			case "had", "put", "sat", "could":
				return "verb"
			case "on":
				return "preposition"
			case "s":
				return "particle"
			case "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
				"ten", "eleven", "twelve":
				return "number"
			default:
				return "noun"
		}
	}
}
#endif
