import Foundation
import SwiftLexicon
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EventContextTests {
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	@Test(arguments: [false, true])
	func supplemental_context_survives_forwarding_without_changing_the_key_or_payload(null: Bool) async throws {
		let key = test.one["Dorothy"].more
		let payload: Event.Value = null ? .null : ["title": "Oz"]
		let original = Event(key, value: payload, date: Date(timeIntervalSinceReferenceDate: 1.25))
		var enriched = original
		enriched.context = [
			"test.one": "Supplemental value, not a binding",
			"origin": ["id": "test.two", "data": ["test.one": "Alice"]],
			"opaque": ["{returns}": ["error": ["message": "Still data"]]],
			"empty": nil
		]
		#expect(original.context.isEmpty)
		#expect(enriched.id == original.id && enriched.date == original.date)
		#expect(enriched.detail == key.detail && enriched.values == original.values)
		#expect(enriched.matches(key) && enriched.matches(I_test_one_more.self))
		#expect(!enriched.matches(test.one["Alice"].more))
		#expect(try enriched[type: Event.Value.self] == payload)
		#expect(try enriched[test.one, as: String.self] == "Dorothy")
		let bus = Events()
		let stream = bus.stream
		try bus.send(enriched)
		bus.finish()
		var received = stream.makeAsyncIterator()
		let event = try #require(await received.next())
		#expect(event == enriched)
		let forwarding = Events()
		var forwarded = forwarding.stream.makeAsyncIterator()
		defer { forwarding.finish() }
		try forwarding.send(event)
		#expect(await forwarded.next() == enriched)
		let snapshot = try decoder.decode(Event.Snapshot.self, from: encoder.encode(event.snapshot))
		#expect(snapshot.context == enriched.context)
		#expect(snapshot.id == original.id && snapshot.date == original.date)
		#expect(snapshot.value == payload && snapshot.values == original.values)
	}

	@Test
	func historical_snapshots_have_empty_context_but_invalid_present_context_is_rejected() throws {
		let event = Event(test.one, value: .null)
		var fields = try #require(JSONSerialization.jsonObject(with: encoder.encode(event.snapshot)) as? [String: Any])
		fields.removeValue(forKey: "context")
		let old = try decoder.decode(Event.Snapshot.self, from: JSONSerialization.data(withJSONObject: fields))
		#expect(old.context.isEmpty && old.value == .null && old.id == event.id)
		for invalid: Any in [NSNull(), "invalid", []] {
			fields["context"] = invalid
			#expect(throws: (any Error).self) {
				try decoder.decode(Event.Snapshot.self, from: JSONSerialization.data(withJSONObject: fields))
			}
		}
	}
}
