//
// github.com/screensailor 2026
//

import Lexicon
import XCTest

final class DocumentPerformanceTests: XCTestCase {

	private static let taskpaper = makeTaskpaper()
	private static let document = try! TaskPaper(taskpaper).decodeDocument()
	private static let documentJSON = try! JSONEncoder().encode(document.json)

	func test_taskpaper_document_decode_performance() {
		measure {
			_ = try! TaskPaper(Self.taskpaper).decodeDocument()
		}
	}

	func test_taskpaper_document_encode_performance() {
		measure {
			_ = TaskPaper.encode(Self.document)
		}
	}

	func test_document_json_encode_performance() {
		let encoder = JSONEncoder()
		measure {
			_ = try! encoder.encode(Self.document.json)
		}
	}

	func test_document_json_decode_performance() {
		let decoder = JSONDecoder()
		measure {
			_ = try! Lexicon.Document(decoder.decode(Lexicon.Document.JSON.self, from: Self.documentJSON))
		}
	}
}

private extension DocumentPerformanceTests {

	static func makeTaskpaper() -> String {
		var lines: [String] = []

		for root in stride(from: 3, through: 0, by: -1) {
			let rootName = "root\(root)"
			lines.append("\(rootName):")
			lines.append("\t# root \(root) comment")
			lines.append("\t> root \(root) note")
			lines.append("\t@ local\(root).lexicon")
			lines.append("\ttype:")

			for child in stride(from: 39, through: 0, by: -1) {
				let childName = "node\(child)"
				lines.append("\t\(childName):")
				lines.append("\t? {\"index\":\(child),\"root\":\(root)}")
				lines.append("\t+ \(rootName).type")

				if root > 0 {
					lines.append("\t+ root0.type")
				}

				for grandchild in stride(from: 3, through: 0, by: -1) {
					lines.append("\t\tchild\(grandchild):")
					lines.append("\t\t? \"\(rootName)-\(childName)-\(grandchild)\"")
				}
			}
		}

		return lines.joined(separator: "\n")
	}
}
