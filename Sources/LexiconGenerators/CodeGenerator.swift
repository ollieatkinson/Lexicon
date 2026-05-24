//
// github.com/screensailor 2022
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import Lexicon

public protocol CodeGenerator: Sendable {
	static var utType: UTType { get }
	static var command: String { get }
	static func generate(_ json: Lexicon.Graph.JSON) throws -> Data
}
