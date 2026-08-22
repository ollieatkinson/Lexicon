//
// github.com/screensailor 2022
//

import Lexicon

@LexiconActor open class L: Hashable, I {
	nonisolated open class var localized: String { "" }
	public let __: String
	nonisolated public required init(_ id: String) { __ = id }
}

public extension L {
	nonisolated static func == (lhs: L, rhs: L) -> Bool { lhs.__ == rhs.__ }
	nonisolated func hash(into hasher: inout Hasher) { hasher.combine(__) }
}
