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
}
