import Foundation
import Testing
import SwiftLexicon

@Suite struct EventDetailCodingTests {
	@Test func contextual_values_round_trip_without_another_identity_model() throws {
		let detail = EventDetail(id: "app.screen", data: [
			"app.user": "Dorothy", "app.count": 1, "app.enabled": true,
			"app.options": ["scale": 1.5, "fallback": nil, "names": ["A", "B"]],
		])
		let encoded = try JSONEncoder().encode(detail)
		let decoded = try JSONDecoder().decode(EventDetail.self, from: encoded)
		#expect(decoded == detail)
		#expect(Set([detail, decoded]).count == 1)
		let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		#expect(object["id"] as? String == "app.screen")
		#expect(object["data"] is [String: Any])
		#expect(decoded.data["app.count"]?.int == 1)
		#expect(decoded.data["app.enabled"]?.bool == true)
	}

	@Test func unbound_ids_decode_concisely_and_malformed_supplied_data_is_rejected() throws {
		let decoder = JSONDecoder()
		for source in [#""app.screen""#, #"{"id":"app.screen"}"#] {
			#expect(try decoder.decode(EventDetail.self, from: Data(source.utf8)) == EventDetail(id: "app.screen", data: [:]))
		}
		for source in [#"{"id":"app.screen","data":null}"#, #"{"id":"app.screen","data":42}"#, #"{"data":{}}"#] {
			#expect(throws: DecodingError.self) { try decoder.decode(EventDetail.self, from: Data(source.utf8)) }
		}
	}

	@Test(arguments: ["test.one[alex].more[2026-10]", #"test.one["4053"].more[true].time[1.5]"#,
		#"test.one[[{"text":"left]right","enabled":false},null]]"#])
	func json_strings_decode_native_contextual_keys(description: String) throws {
		let key = try K<L_test_one_more_time>(bracketed: description)
		let decoded = try JSONDecoder().decode(EventDetail.self, from: JSONEncoder().encode(key.bracketed))
		#expect(decoded == key.detail)
		#expect(try JSONDecoder().decode(EventDetail.self, from: JSONEncoder().encode(decoded)) == key.detail)
	}

	@Test func off_path_scope_keeps_the_existing_object_representation() throws {
		let key = try K(test.one, values: [test.one: "1", test.one.more: ["nested": [true, nil, 2]]])
		let decoded = try JSONDecoder().decode(EventDetail.self, from: JSONEncoder().encode(key.bracketed))
		#expect(decoded == key.detail)
		let encoded = try JSONEncoder().encode(decoded)
		#expect(try JSONSerialization.jsonObject(with: encoded) is [String: Any])
		#expect(try JSONDecoder().decode(EventDetail.self, from: encoded) == key.detail)
	}

	@Test(arguments: ["", "test.one[two", "test.one]"])
	func malformed_contextual_strings_report_their_json_location(description: String) throws {
		struct Record: Decodable { let reference: EventDetail }
		let encoded = try JSONEncoder().encode(["reference": description])
		do {
			_ = try JSONDecoder().decode(Record.self, from: encoded)
			Issue.record("Expected an invalid contextual key")
		} catch DecodingError.dataCorrupted(let context) {
			#expect(context.codingPath.map(\.stringValue) == ["reference"])
		}
	}
}
