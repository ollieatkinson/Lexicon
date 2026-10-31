import Foundation
import Testing
import SwiftLexicon

@Suite(.timeLimit(.minutes(1))) struct ContextualEventTests {
	@Test func native_scope_values_survive_generated_traversal_and_description_round_trips() throws {
		let scope: [L: Event.Value] = [test.one: "entity", test.two: ["items": [1, true, nil]]]
		let key = try K(test.one, values: scope).more.time
		let detail = key.detail
		#expect(detail.data == ["test.one": "entity", "test.two": ["items": [1, true, nil]]])
		#expect(try EventDetail(bracketed: key.bracketed) == detail)
		#expect(try K<L_test_one_more_time>(bracketed: key.bracketed).detail == detail)
		#expect(try K(test.one, values: [test.one: 1]).bracketed == test.one[1].bracketed)
		let partialPrefix = try K(test.one, values: [L("test.on"): "other"])
		#expect(try EventDetail(bracketed: partialPrefix.bracketed) == partialPrefix.detail)
		#expect(throws: (any Error).self) { try K(test.one, values: [test.two: .double(.infinity)]) }
	}

	@Test(arguments: [false, true])
	func explicit_payloads_keep_self_bindings_native_matching_and_snapshot_null_distinctions(null: Bool) async throws {
		let key = try K(test.one, values: [test.one: "entity", test.two: true])
		let value: Event.Value = null ? .null : ["name": "Dorothy", "none": nil]
		let event = Event(key, value: value)
		#expect(event.detail == key.detail && event.k.____ == key.____)
		#expect(event.matches(test.one["entity"]) && event.matches(I_test_type_odd.self))
		#expect(!event.matches(test.one["other"]))
		let payload: Event.Value = try event[type: Event.Value.self]
		let entity: String = try event[test.one, as: String.self]
		#expect(payload == value && entity == "entity")
		let snapshot = try JSONDecoder().decode(Event.Snapshot.self, from: JSONEncoder().encode(event.snapshot))
		#expect(snapshot.value == value && snapshot.values == event.values && snapshot.id == event.id)
		let original = Event(test.one["old"])
		let oldSnapshot = try JSONDecoder().decode(Event.Snapshot.self, from: JSONEncoder().encode(original.snapshot))
		#expect(oldSnapshot.value == nil && original.value == nil)
		#expect(try original[type: String.self] == "old")

		let events = Events()
		let (matches, continuation) = AsyncStream<Event>.makeStream()
		let observer = events.on(test.one["entity"]) { continuation.yield($0) }
		defer { observer.cancel(); events.finish(); continuation.finish() }
		try events.send(Event(K(test.one, values: [test.one: "other"]), value: value))
		try events.send(event)
		events.finish()
		await observer.wait()
		continuation.finish()
		var iterator = matches.makeAsyncIterator()
		#expect(await iterator.next()?.id == event.id)
		#expect(await iterator.next() == nil)
	}
}
