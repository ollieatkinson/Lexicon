//
// github.com/screensailor 2026
//

import XCTest
import _Collections

final class SortedDictionaryTests: XCTestCase {

	func test_dictionary_literal_sorts_keys() {
		let dictionary: SortedDictionary<String, Int> = [
			"zeta": 3,
			"alpha": 1,
			"middle": 2,
		]

		XCTAssertEqual(Array(dictionary.keys), ["alpha", "middle", "zeta"])
		XCTAssertEqual(Array(dictionary.values), [1, 2, 3])
	}

	func test_subscript_insert_keeps_keys_sorted() {
		var dictionary = SortedDictionary<String, Int>()

		dictionary["zeta"] = 3
		dictionary["alpha"] = 1
		dictionary["middle"] = 2

		XCTAssertEqual(Array(dictionary.keys), ["alpha", "middle", "zeta"])
		XCTAssertEqual(Array(dictionary.values), [1, 2, 3])
	}

	func test_subscript_update_preserves_existing_position() {
		var dictionary: SortedDictionary<String, Int> = [
			"alpha": 1,
			"middle": 2,
			"zeta": 3,
		]

		dictionary["middle"] = 20

		XCTAssertEqual(Array(dictionary.keys), ["alpha", "middle", "zeta"])
		XCTAssertEqual(Array(dictionary.values), [1, 20, 3])
	}

	func test_subscript_nil_removes_value() {
		var dictionary: SortedDictionary<String, Int> = [
			"alpha": 1,
			"middle": 2,
			"zeta": 3,
		]

		dictionary["middle"] = nil

		XCTAssertEqual(Array(dictionary.keys), ["alpha", "zeta"])
		XCTAssertEqual(Array(dictionary.values), [1, 3])
	}
}
