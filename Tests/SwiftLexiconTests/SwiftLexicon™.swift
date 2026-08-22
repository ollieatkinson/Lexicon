//
// github.com/screensailor 2022
//
import Testing
import Foundation
@_exported import Lexicon
@_exported import SwiftLexicon
import AsyncAlgorithms

@Suite

struct SwiftLexicon™ {
	@Test
	func test_code() throws {

		#expect(test.one.more.time.one.more.time(\.id) == "test.one.more.time.one.more.time")

		#expect(test.two.bad == test.two.no.good)
		#expect(test.two.bad(\.id) == "test.two.no.good")
	}

	@Test
	func test_events() async throws {

		let l = test.one.more.time.one

		let events = Events()
		let results = AsyncChannel<Event>()
		let collected = Task {
			await collect(1, from: results)
		}

		let o = l >> events.handler { event in
			await results.send(event)
		}
		defer {
			o.cancel()
			results.finish()
		}

		try events.send(Event(l))

		let result = try await collected.value.first.try()

		#expect(result.l == l)
	}

	@Test
	func test_Event() async throws {

		let k = test.one[1].more[2].time["3"].one[0]
		let l = k.___

		#expect(l == test.one.more.time.one)

		#expect(k(\.id) == #"test.one[1].more[2].time["3"].one[0]"#)

		let events = Events()
		let results = AsyncChannel<Event>()
		let collected = Task {
			await collect(1, from: results)
		}

		let o = l >> events.handler { event in
			await results.send(event)
		}
		defer {
			o.cancel()
			results.finish()
		}

		try events.send(Event(k))

		let x = try await collected.value.first.try()

		#expect(x.k(\.id) == k(\.id))

		#expect(try x[] == 0)
		#expect(try x[test.one] == 1)
		#expect(try x[test.one.more] == 2)
		#expect(try x[test.one.more.time] == "3")
	}

	@Test
	func test_Event_snapshot_Codable() throws {

		let event = Event(test.one[1].more["two"])
		let data = try JSONEncoder().encode(event.snapshot)
		let snapshot = try JSONDecoder().decode(Event.Snapshot.self, from: data)

		#expect(snapshot.id == event.id)
		#expect(snapshot.description == "test.one[1].more[two]")
		#expect(snapshot.lemma == "test.one.more")
		#expect(snapshot.values["test.one"]?.int == 1)
		#expect(snapshot.values["test.one.more"]?.string == "two")
	}

	@Test
	func test_Event_snapshot_encodes_Codable_payloads_as_JSON() throws {

		let payload = EventPayload(name: "lexicon", count: 2)
		let event = Event(try test.one.encoding(payload))
		let value = try event.snapshot.values["test.one"].try()
		let decoded: EventPayload = try event[test.one]
		let decodedUsingDecoder: EventPayload = try event[test.one, as: EventPayload.self, using: JSONDecoder()]

		#expect(value.object?["name"]?.string == payload.name)
		#expect(value.object?["count"]?.int == payload.count)
		#expect(decoded == payload)
		#expect(decodedUsingDecoder == payload)
	}

	@Test
	func test_Event_encoding_propagates_payload_failures() {
		let payload = FailingEventPayload()

		do {
			_ = try test.one.encoding(payload)
			Issue.record("Expected event payload encoding to fail.")
		} catch is FailingEventPayload.EncodingFailure {
			// Expected.
		} catch {
			Issue.record("Unexpected event payload encoding error: \(error)")
		}
	}

	@Test
	func test_Event_floating_point_values_use_the_throwing_encoding_path() throws {
		let event = Event(try test.one.encoding(1.5))
		let value: Double = try event[test.one]

		#expect(value == 1.5)
		#expect(throws: (any Error).self) {
			_ = try test.one.encoding(Double.nan)
		}
		#expect(throws: (any Error).self) {
			_ = try test.one.encoding(Float.infinity)
		}
	}

	@Test
	func test_Event_JSON_values_validate_recursively_and_round_trip() throws {
		let value: Event.Value = .object([
			"nested": .array([
				.int(1),
				.double(1.5),
				.object(["enabled": .bool(true)]),
			]),
		])
		let key = try test.one[value]
		let reparsed = try K<L_test_one>(bracketed: key.bracketed)
		let event = Event(key)
		let snapshotData = try JSONEncoder().encode(event.snapshot)
		let snapshot = try JSONDecoder().decode(Event.Snapshot.self, from: snapshotData)
		let decoded: Event.Value = try event[test.one]

		#expect(key.____[test.one] == value)
		#expect(reparsed.____[test.one] == value)
		#expect(snapshot.values["test.one"] == value)
		#expect(decoded == value)
	}

	@Test
	func test_Event_JSON_values_reject_nested_nonfinite_numbers() {
		let invalidValues: [Event.Value] = [
			.array([
				.object(["nan": .double(.nan)]),
			]),
			.object([
				"infinities": .array([
					.double(.infinity),
					.double(-.infinity),
				]),
			]),
		]

		for value in invalidValues {
			#expect(throws: (any Error).self) {
				_ = try test.one[value]
			}
			#expect(throws: (any Error).self) {
				_ = try test.one[1].more[value]
			}
		}
	}

	@Test
	func test_Event_typed_String_access_rejects_non_string_values() throws {

		let event = Event(test.one[1])
		var didThrow = false

		do {
			let _: String = try event[test.one]
		} catch {
			didThrow = true
		}

		#expect(didThrow == true)
	}

	@Test
	func test_Event_granularity() async throws {

		let events = Events()

		let ticks = AsyncChannel<String>()
		let all = AsyncChannel<String>()
		let collectedTicks = Task {
			await collect(2, from: ticks)
		}
		let collectedAll = Task {
			await collect(3, from: all)
		}

		let oTicks = test.one.more.time["✅"].one >> events.handler { event in
			guard let o: String = try? event[test.one.more.time] else {
				return
			}
			await ticks.send(o)
		}

		let oAll = I_test_one.self >> events.handler { event in
			guard let o: String = try? event[test.one.more.time] else {
				return
			}
			await all.send(o)
		}
		defer {
			oTicks.cancel()
			oAll.cancel()
			ticks.finish()
			all.finish()
		}

		try events.send(Event(test.one[1].more[1].time["✅"].one[1]))
		try events.send(Event(test.one[2].more[2].time["❌"].one[2]))
		try events.send(Event(test.one[3].more[3].time["✅"].one[3]))

		let tickValues = await collectedTicks.value
		let allValues = await collectedAll.value
		#expect(tickValues == ["✅", "✅"])
		#expect(allValues == ["✅", "❌", "✅"])
	}
}

private func collect<Value>(_ count: Int, from channel: AsyncChannel<Value>) async -> [Value] {
	var values: [Value] = []
	for await value in channel {
		values.append(value)
		if values.count == count {
			break
		}
	}
	return values
}

private struct EventPayload: Codable, Hashable, Sendable {
	var name: String
	var count: Int
}

private struct FailingEventPayload: Encodable, Hashable, Sendable {
	enum EncodingFailure: Error {
		case expected
	}

	func encode(to encoder: any Encoder) throws {
		throw EncodingFailure.expected
	}
}

// MARK: ↓ demonstrating the limitations of purely static type constraints

extension SwiftLexicon™ {

	private var eventL: Event { Event(test.one) }

	@Test
	func test_Event_L_is_L() throws {
		#expect(!(eventL.matches(test)))
		#expect(eventL.matches(test.one))
		#expect(!(eventL.matches(test.two)))
		#expect(!(eventL.matches(test.type.odd)))
	}

	@Test
	func test_Event_L_is_I() throws {
		#expect(eventL.matches(I_test_one.self))
		#expect(eventL.l is I_test_one)
		#expect(!(eventL.l is I_test_two))
		#expect(eventL.l is I_test_type_odd)
	}

	@Test
	func test_Event_L_is_any_I() throws {
		#expect(eventL.matches(test.one as I))
		#expect(!(eventL.matches(test.two as I)))
		#expect(!(eventL.matches(test.one[4] as I)))
	}

	@Test
	func test_Event_L_is_K() throws {
		#expect(!(eventL.matches(test.one[4])))
		#expect(!(eventL.matches(test.two[4])))
	}
}

extension SwiftLexicon™ {

	private var eventK: Event { Event(test.one[4].good) }

	@Test
	func test_Event_K_is_L() throws {
		#expect(!(eventK.matches(test)))
		#expect(!(eventK.matches(test.one)))
		#expect(eventK.matches(test.one.good))
		#expect(!(eventK.matches(test.type.odd.good)))
	}

	@Test
	func test_Event_K_is_I() throws {
		#expect(!(eventK.l is I_test))
		#expect(!(eventK.l is I_test_one))
		#expect(eventK.l is I_test_type_odd_good)
	}

	@Test
	func test_Event_K_is_any_I() throws {
		#expect(!(eventK.matches(test.two.no.good as I)))
		#expect(eventK.matches(test.one.good as I))
		#expect(!(eventK.matches(test.one[4] as I)))
		#expect(!(eventK.matches(test.one[2].good as I)))
		#expect(eventK.matches(test.one[4].good as I))
		#expect(!(eventK.matches(test.type.odd[4].good as I)))
	}

	@Test
	func test_Event_K_is_K() throws {
		#expect(!(eventK.matches(test.one[4])))
		#expect(!(eventK.matches(test.one[2].good)))
		#expect(eventK.matches(test.one[4].good))
		#expect(!(eventK.matches(test.type.odd[4].good)))
	}
}
