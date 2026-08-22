//
// github.com/screensailor 2026
//
import Testing
import _Collections

@Suite

struct SortedDictionaryTests {

	@Test
	func test_dictionary_literal_sorts_keys() {
		let dictionary: SortedDictionary<String, Int> = [
			"zeta": 3,
			"alpha": 1,
			"middle": 2,
		]

		#expect(Array(dictionary.keys) == ["alpha", "middle", "zeta"])
		#expect(Array(dictionary.keysInOrder) == ["alpha", "middle", "zeta"])
		#expect(Array(dictionary.values) == [1, 2, 3])
		#expect(dictionary.valuesInKeyOrder == [1, 2, 3])
	}

	@Test
	func test_subscript_insert_keeps_keys_sorted() {
		var dictionary = SortedDictionary<String, Int>()

		dictionary["zeta"] = 3
		dictionary["alpha"] = 1
		dictionary["middle"] = 2

		#expect(Array(dictionary.keys) == ["alpha", "middle", "zeta"])
		#expect(Array(dictionary.values) == [1, 2, 3])
	}

	@Test
	func test_subscript_update_preserves_existing_position() {
		var dictionary: SortedDictionary<String, Int> = [
			"alpha": 1,
			"middle": 2,
			"zeta": 3,
		]

		dictionary["middle"] = 20

		#expect(Array(dictionary.keys) == ["alpha", "middle", "zeta"])
		#expect(Array(dictionary.values) == [1, 20, 3])
	}

	@Test
	func test_subscript_nil_removes_value() {
		var dictionary: SortedDictionary<String, Int> = [
			"alpha": 1,
			"middle": 2,
			"zeta": 3,
		]

		dictionary["middle"] = nil

		#expect(Array(dictionary.keys) == ["alpha", "zeta"])
		#expect(Array(dictionary.values) == [1, 3])
	}
}
