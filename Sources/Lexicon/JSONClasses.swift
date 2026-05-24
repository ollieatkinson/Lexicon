//
// github.com/screensailor 2022
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum JSONClasses: CodeGenerator {
	
	public static let utType: UTType = .json
	public static let command = "json"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		let encoder = Encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(json)
	}
	
	public class Encoder: JSONEncoder, @unchecked Sendable {
		public override init() {
			super.init()
			self.dateEncodingStrategy = .formatted(JSONClasses.makeDateFormatter())
		}
	}
	
	public class Decoder: JSONDecoder, @unchecked Sendable {
		public override init() {
			super.init()
			self.dateDecodingStrategy = .formatted(JSONClasses.makeDateFormatter())
		}
	}
	
	private static func makeDateFormatter() -> Foundation.DateFormatter {
		let o = Foundation.DateFormatter()
		o.calendar = Calendar(identifier: .iso8601)
		o.locale = Locale(identifier: "en_US_POSIX")
		o.timeZone = TimeZone(secondsFromGMT: 0)
		o.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
		return o
	}
}
