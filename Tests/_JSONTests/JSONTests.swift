//
// github.com/screensailor 2026
//

import Foundation
import XCTest
@testable import _JSON

final class JSONTests: XCTestCase {

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

		XCTAssertEqual(decoded, value)
		XCTAssertEqual(try decoded[["b", 2] as JSONPath, as: String.self], "last")
		XCTAssertEqual(decoded["missing"], .null)
		XCTAssertEqual(decoded["nested", "ok"].bool, true)
	}

	func test_foundation_encoding_decoding_bridges_codable_values() throws {
		struct Payload: Codable, Equatable {
			var name: String
			var count: Int
			var flags: [Bool]
		}

		let payload = Payload(name: "lexicon", count: 3, flags: [true, false])
		let json = try JSON.encoded(payload)

		XCTAssertEqual(json["name"].string, "lexicon")
		XCTAssertEqual(json["count"].int, 3)
		XCTAssertEqual(json["flags", 0].bool, true)

		let decoded = try json.decode(Payload.self)
		XCTAssertEqual(decoded, payload)
	}

	func test_foundation_number_bridging_preserves_json_shape() throws {
		let bool = try JSON(jsonObject: NSNumber(value: true))
		XCTAssertEqual(bool.bool, true)
		XCTAssertNil(bool.int)

		let smallUnsigned = try JSON(jsonObject: NSNumber(value: UInt64(42)))
		XCTAssertEqual(smallUnsigned.int, 42)

		let largeUnsigned = UInt64(Int64.max) + 1
		let largeUnsignedJSON = try JSON(jsonObject: NSNumber(value: largeUnsigned))
		XCTAssertNil(largeUnsignedJSON.int)
		XCTAssertEqual(largeUnsignedJSON.double, Double(largeUnsigned))

		let maxUnsignedJSON = try JSON(jsonObject: NSNumber(value: UInt64.max))
		XCTAssertNil(maxUnsignedJSON.int)
		XCTAssertEqual(maxUnsignedJSON.double, Double(UInt64.max))

		let fractional = try JSON(jsonObject: NSNumber(value: 1.25))
		XCTAssertNil(fractional.int)
		XCTAssertEqual(fractional.double, 1.25)
	}

	func test_casting_error_describes_underlying_json_value() throws {
		do {
			_ = try JSON.string("lexicon")[as: Int.self]
			XCTFail("Expected cast to fail.")
		} catch let error as CastingError {
			XCTAssert(error.valueType == String.self)
		}
	}

	func test_path_mutation_extends_arrays_and_supports_negative_indices() throws {
		var value: JSON = [:]

		value["items", 2] = "third"

		XCTAssertEqual(value["items"].array?.count, 3)
		XCTAssertTrue(value["items", 0].isNull)
		XCTAssertEqual(try value[["items", -1] as JSONPath, as: String.self], "third")
	}
}
