import Foundation
import SwiftLexicon
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EventDateTests {
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	@Test(arguments: [false, true], [false, true])
	func creation_date_survives_buffered_delivery_forwarding_and_snapshot_coding(
		keyed: Bool,
		payload: Bool
	) async throws {
		let date = Date(timeIntervalSince1970: 1_700_000_000.125)
		let key = test.one["Dorothy"].more
		let value: Event.Value? = payload ? .null : nil
		let event = keyed
			? Event(key, value: value, date: date)
			: Event(test.one, value: value, date: date)
		let events = Events()
		let stream = events.stream
		try events.send(event)
		events.finish()
		// Read only after the publisher closes: delivery must not stamp a new time.
		var iterator = stream.makeAsyncIterator()
		let received = try #require(await iterator.next())
		#expect(received.id == event.id && received.date == date)
		#expect(received.value == value && received.detail == event.detail)
		let forwarded = Events()
		var forwardedEvents = forwarded.stream.makeAsyncIterator()
		defer { forwarded.finish() }
		try forwarded.send(received)
		#expect(await forwardedEvents.next()?.date == date)
		let snapshot = try decoder.decode(Event.Snapshot.self, from: encoder.encode(received.snapshot))
		#expect(snapshot.date == date)
		#expect(snapshot.value == value && snapshot.values == event.values)
		#expect(Event(key, date: date).id != event.id)
	}

	@Test
	func ordinary_construction_captures_time_without_changing_initializer_function_values() {
		let create: (L) -> Event = Event.init
		let createKey: (K<L_test_one>) -> Event = Event.init
		let before = Date.now
		let events = [create(test.one), createKey(test.one["Dorothy"]), Event(test.one, value: .null)]
		let after = Date.now
		#expect(events.allSatisfy { before <= $0.date && $0.date <= after })
		#expect(events.last?.value == .null)
	}

	@Test
	func historical_snapshots_do_not_invent_a_creation_date() throws {
		let event = Event(test.one, value: .null)
		var fields = try #require(JSONSerialization.jsonObject(with: encoder.encode(event.snapshot)) as? [String: Any])
		fields.removeValue(forKey: "date")
		let snapshot = try decoder.decode(Event.Snapshot.self, from: JSONSerialization.data(withJSONObject: fields))
		#expect(snapshot.date == nil)
		#expect(snapshot.value == .null && snapshot.id == event.id)
	}
}
