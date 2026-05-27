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

		let o = l >> events.then { event in
			await results.send(event)
		}
		defer {
			o.cancel()
			results.finish()
		}

		await events.send(Event(l)).value

		let result = try await collected.value.first.try()

		#expect(result.l == l)
	}

	@Test
	func test_Event() async throws {

		let k = test.one[1].more[2].time["3"].one[0]
		let l = k.___

		#expect(l == test.one.more.time.one)

		#expect(k(\.id) == "test.one[1].more[2].time[3].one[0]")

		let events = Events()
		let results = AsyncChannel<Event>()
		let collected = Task {
			await collect(1, from: results)
		}

		let o = l >> events.then { event in
			await results.send(event)
		}
		defer {
			o.cancel()
			results.finish()
		}

		await events.send(Event(k)).value

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
		let event = Event(test.one[payload])
		let value = try event.snapshot.values["test.one"].try()
		let decoded: EventPayload = try event[test.one]
		let decodedUsingDecoder: EventPayload = try event[test.one, as: EventPayload.self, using: JSONDecoder()]

		#expect(value.object?["name"]?.string == payload.name)
		#expect(value.object?["count"]?.int == payload.count)
		#expect(decoded == payload)
		#expect(decodedUsingDecoder == payload)
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

		let oTicks = test.one.more.time["✅"].one >> events.then { event in
			guard let o: String = try? event[test.one.more.time] else {
				return
			}
			await ticks.send(o)
		}

		let oAll = I_test_one.self >> events.then { event in
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

		await events.send(Event(test.one[1].more[1].time["✅"].one[1])).value
		await events.send(Event(test.one[2].more[2].time["❌"].one[2])).value
		await events.send(Event(test.one[3].more[3].time["✅"].one[3])).value

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

// MARK: ↓ demonstrating the limitations of purely static type constraints

extension SwiftLexicon™ {

	private var eventL: Event { Event(test.one) }

	@Test
	func test_Event_L_is_L() throws {
		#expect(!(eventL.is(test)))
		#expect(eventL.is(test.one))
		#expect(!(eventL.is(test.two)))
		#expect(!(eventL.is(test.type.odd)))
	}

	@Test
	func test_Event_L_is_I() throws {
		#expect(eventL.is(I_test_one.self))
		#expect(eventL.l is I_test_one)
		#expect(!(eventL.l is I_test_two))
		#expect(eventL.l is I_test_type_odd)
	}

	@Test
	func test_Event_L_is_any_I() throws {
		#expect(eventL.is(test.one as I))
		#expect(!(eventL.is(test.two as I)))
		#expect(!(eventL.is(test.one[4] as I)))
	}

	@Test
	func test_Event_L_is_K() throws {
		#expect(!(eventL.is(test.one[4])))
		#expect(!(eventL.is(test.two[4])))
	}
}

extension SwiftLexicon™ {

	private var eventK: Event { Event(test.one[4].good) }

	@Test
	func test_Event_K_is_L() throws {
		#expect(!(eventK.is(test)))
		#expect(!(eventK.is(test.one)))
		#expect(eventK.is(test.one.good))
		#expect(!(eventK.is(test.type.odd.good)))
	}

	@Test
	func test_Event_K_is_I() throws {
		#expect(!(eventK.l is I_test))
		#expect(!(eventK.l is I_test_one))
		#expect(eventK.l is I_test_type_odd_good)
	}

	@Test
	func test_Event_K_is_any_I() throws {
		#expect(!(eventK.is(test.two.no.good as I)))
		#expect(eventK.is(test.one.good as I))
		#expect(!(eventK.is(test.one[4] as I)))
		#expect(!(eventK.is(test.one[2].good as I)))
		#expect(eventK.is(test.one[4].good as I))
		#expect(!(eventK.is(test.type.odd[4].good as I)))
	}

	@Test
	func test_Event_K_is_K() throws {
		#expect(!(eventK.is(test.one[4])))
		#expect(!(eventK.is(test.one[2].good)))
		#expect(eventK.is(test.one[4].good))
		#expect(!(eventK.is(test.type.odd[4].good)))
	}
}
