//
// github.com/screensailor 2022
//

import Foundation
import Lexicon

extension String {
	
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
}

extension Data {
	
	func string(encoding: String.Encoding = .utf8) throws -> String {
		try String(data: self, encoding: encoding).try()
	}
}
