//
// github.com/screensailor 2022
//

import Foundation

extension String {
    
    func json<A: Decodable>(as: A.Type = A.self, using decoder: JSONDecoder = .init()) throws -> A {
		try decoder.decode(A.self, from: "\(self).json".file())
    }
	
	func taskpaper() throws -> String {
		try "\(self).taskpaper".file().string()
	}
	
	func file() throws -> Data {
		guard let url = Bundle.module.url(forResource: "Resources/\(self)", withExtension: nil) else {
			throw LexiconError("Could not find '\(self)'")
		}
		return  try Data(contentsOf: url)
	}
	
	func lexicon() async throws -> Lexicon {
		let document = try TaskPaper(self).decodeDocument()
		guard let root = document.roots.keys.first else {
			throw LexiconError("A lexicon document must declare a root")
		}
		return try await Lexicon(document: document, selectedRoot: root)
	}
	
	func lemma(_ id: String) async throws -> Lemma {
		try await lexicon()[Lemma.ID(parsing: id)].try()
	}
}

extension Lexicon {
	
	func taskpaper() -> String {
		TaskPaper.encode(graph)
	}
}

extension Lemma {
	
	func taskpaper() -> String {
		if parent == nil {
			return TaskPaper.encode(document)
		} else {
			return TaskPaper.encode(graph)
		}
	}
}
