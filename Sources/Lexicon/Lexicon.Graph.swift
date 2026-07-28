//
// github.com/screensailor 2021
//

import Foundation

public extension Lexicon {

	struct Graph: Sendable, Equatable {

		public typealias Path = [Lemma.Name]

		public var date: Date
		public var rootName: Lemma.Name
		public var root: Node

		public init(
			name: Lemma.Name = "root",
			date: Date = Document.unspecifiedDate
		) {
			self.date = date
			self.rootName = name
			self.root = Node()
		}

		public init(
			rootName: Lemma.Name,
			root: Node,
			date: Date = Document.unspecifiedDate
		) {
			self.date = date
			self.rootName = rootName
			self.root = root
		}

		public var rootID: Lemma.ID {
			Lemma.ID(root: rootName)
		}
	}
}

public extension Lexicon.Graph {

	subscript(_ path: Path) -> Node {
		get { root[path: path[...]] }
		set { root[path: path[...]] = newValue }
	}
}

extension Lexicon.Graph.Node {

	subscript<Path>(path path: Path) -> Self where Path: Collection, Path.Element == Lemma.Name {
		get {
			guard let name = path.first else {
				return self
			}
			return self[name][path: path.dropFirst()]
		}
		set {
			guard let name = path.first else {
				self = newValue
				return
			}
			var child = self[name]
			child[path: path.dropFirst()] = newValue
			children[name] = child
		}
	}
}

extension Lexicon.Graph: CustomStringConvertible {

	public var description: String {
		"\(Self.self)(root: \(rootName), date: \(date))"
	}
}

#if canImport(NaturalLanguage)
import NaturalLanguage

public extension Lexicon.Graph {

	static let underscore = CharacterSet(charactersIn: "_")
	static let specialSentenceTerminator = CharacterSet(charactersIn: ";–()[]{}")

	static func from(sentences string: String, root name: Lemma.Name = "a") -> Lexicon.Graph {
		var graph = Lexicon.Graph(name: name)
		graph.root.make(child: "word")
		graph.root.make(child: "sentence")

		let tagger = NLTagger(tagSchemes: [.lexicalClass])
		let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
		let sentences = NLTokenizer(unit: .sentence)
		sentences.string = string

		sentences.enumerateTokens(in: string.indices.range) { range, _ in
			var nodePath: Path = ["sentence"]

			for sentence in string[range].components(separatedBy: specialSentenceTerminator) {
				tagger.string = sentence
				tagger.enumerateTags(
					in: sentence.indices.range,
					unit: .word,
					scheme: .lexicalClass,
					options: options
				) { tag, range in
					guard
						let token = tag?.rawValue.lowercased(),
						let tokenName = try? Lemma.Name(validating: token)
					else {
						return true
					}

					var candidate = sentence[range]
						.lowercased()
						.trimmingCharacters(in: underscore)
						.filter { character in
							character == "_" || character.isLetter || character.isNumber
						}
					if candidate.first?.isNumber == true {
						candidate = "_\(candidate)"
					}
					guard let childName = try? Lemma.Name(validating: candidate) else {
						return true
					}

					graph[nodePath].make(child: childName)
					nodePath.append(childName)
					graph[["word"]].make(child: tokenName)
					graph[nodePath].type.insert(
						graph.rootID.appending(Lemma.Name(stringLiteral: "word")).appending(tokenName)
					)
					return true
				}
			}
			return true
		}
		return graph
	}
}
#else
public extension Lexicon.Graph {

	static func from(sentences string: String, root name: Lemma.Name = "a") -> Lexicon.Graph {
		var graph = Lexicon.Graph(name: name)
		graph.root.make(child: "word")
		graph.root.make(child: "sentence")

		for sentenceString in string.components(separatedBy: sentenceSeparators) {
			var nodePath: Path = ["sentence"]
			for word in Self.words(in: sentenceString) {
				guard
					let wordName = try? Lemma.Name(validating: word),
					let className = try? Lemma.Name(validating: Self.lexicalClass(for: word))
				else {
					continue
				}
				graph[nodePath].make(child: wordName)
				nodePath.append(wordName)
				graph[["word"]].make(child: className)
				graph[nodePath].type.insert(
					graph.rootID.appending(Lemma.Name(stringLiteral: "word")).appending(className)
				)
			}
		}
		return graph
	}
}

private extension Lexicon.Graph {

	static let sentenceSeparators = CharacterSet.newlines.union(
		CharacterSet(charactersIn: ".!?;–()[]{}")
	)

	static func words(in sentence: String) -> [String] {
		sentence
			.replacingOccurrences(of: "n't", with: " nt", options: .caseInsensitive)
			.replacingOccurrences(of: "n’t", with: " nt", options: .caseInsensitive)
			.components(separatedBy: CharacterSet.alphanumerics.union(
				CharacterSet(charactersIn: "_")
			).inverted)
			.compactMap { word -> String? in
				var word = word.lowercased().trimmingCharacters(
					in: CharacterSet(charactersIn: "_")
				)
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
			case "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
				"nine", "ten", "eleven", "twelve":
				return "number"
			default:
				return "noun"
		}
	}
}
#endif
