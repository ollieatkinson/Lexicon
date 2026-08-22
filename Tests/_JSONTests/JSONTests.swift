//
// github.com/screensailor 2026
//

import Testing
import Foundation
@testable import _JSON

@Suite

struct JSONTests {

	@Test
	func test_codable_round_trip_preserves_json_shape() throws {
		let value: JSON = [
			"b": [true, nil, "last"],
			"a": 1,
			"nested": [
				"ok": true
			]
		]

		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(JSON.self, from: data)

		#expect(decoded == value)
		#expect(try decoded[["b", 2] as JSONPath, as: String.self] == "last")
		#expect(decoded["missing"] == .null)
		#expect(decoded["nested", "ok"].bool == true)
	}

	@Test
	func test_foundation_encoding_decoding_bridges_codable_values() throws {
		struct Payload: Codable, Equatable {
			var name: String
			var count: Int
			var flags: [Bool]
		}

		let payload = Payload(name: "lexicon", count: 3, flags: [true, false])
		let json = try JSON.encoded(payload)

		#expect(json["name"].string == "lexicon")
		#expect(json["count"].int == 3)
		#expect(json["flags", 0].bool == true)

		let decoded = try json.decode(Payload.self)
		#expect(decoded == payload)
	}

	@Test
	func test_foundation_number_bridging_preserves_json_shape() throws {
		let bool = try JSON(jsonObject: NSNumber(value: true))
		#expect(bool.bool == true)
		#expect(bool.int == nil)

		let smallUnsigned = try JSON(jsonObject: NSNumber(value: UInt64(42)))
		#expect(smallUnsigned.int == 42)

		let largeUnsigned = UInt64(Int64.max) + 1
		let largeUnsignedJSON = try JSON(jsonObject: NSNumber(value: largeUnsigned))
		#expect(largeUnsignedJSON.int == nil)
		#expect(largeUnsignedJSON.double == Double(largeUnsigned))

		let maxUnsignedJSON = try JSON(jsonObject: NSNumber(value: UInt64.max))
		#expect(maxUnsignedJSON.int == nil)
		#expect(maxUnsignedJSON.double == Double(UInt64.max))

		let fractional = try JSON(jsonObject: NSNumber(value: 1.25))
		#expect(fractional.int == nil)
		#expect(fractional.double == 1.25)
	}

	@Test
	func test_casting_error_describes_underlying_json_value() throws {
		do {
			_ = try JSON.string("lexicon")[as: Int.self]
			Issue.record("Expected cast to fail.")
		} catch let error as CastingError {
			#expect(ObjectIdentifier(error.valueType) == ObjectIdentifier(String.self))
		}
	}

	@Test
	func test_numeric_equality_and_hash_survive_integral_double_round_trip() throws {
		let value = JSON.double(1.0)
		let decoded = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(value))

		#expect(decoded == value)
		#expect(Set([decoded, value]).count == 1)
		#expect(decoded.int == 1)
	}

	@Test
	func test_throwing_path_mutation_replaces_or_appends_without_sparse_allocation() throws {
		var value: JSON = [:]

		try value.set("first", at: ["items", 0] as JSONPath)
		try value.set("second", at: ["items", 1] as JSONPath)
		try value.set("updated", at: ["items", -1] as JSONPath)

		#expect(value["items"].array?.count == 2)
		#expect(try value[["items", 0] as JSONPath, as: String.self] == "first")
		#expect(try value[["items", -1] as JSONPath, as: String.self] == "updated")

		let unchanged = value
		#expect(throws: JSONMutationError.arrayIndexOutOfBounds(index: 3, count: 2)) {
			try value.set("sparse", at: ["items", 3] as JSONPath)
		}
		#expect(value == unchanged)
	}
}
