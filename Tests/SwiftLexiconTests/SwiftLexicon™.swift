//
// github.com/screensailor 2022
//

@_exported import Hope
@_exported import Lexicon
@_exported import SwiftLexicon
import AsyncAlgorithms

final class SwiftLexicon™: Hopes {

	func test_generator() async throws {

		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try Generator.generate(json).string()

		try hope(code) == "test.swift".file().string()
	}

	func test_code() throws {

		hope(test.one.more.time.one.more.time(\.id)) == "test.one.more.time.one.more.time"

		hope(test.two.bad) == test.two.no.good
		hope(test.two.bad(\.id)) == "test.two.no.good"
	}

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

		hope(result.l) == l
	}

	func test_Event() async throws {

		let k = test.one[1].more[2].time["3"].one[0]
		let l = k.___

		hope(l) == test.one.more.time.one

		hope(k(\.id)) == "test.one[1].more[2].time[3].one[0]"

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

		hope(x.k(\.id)) == k(\.id)

		try hope(x[]) == 0
		try hope(x[test.one]) == 1
		try hope(x[test.one.more]) == 2
		try hope(x[test.one.more.time]) == "3"
	}

	func test_Event_snapshot_Codable() throws {

		let event = Event(test.one[1].more["two"])
		let data = try JSONEncoder().encode(event.snapshot)
		let snapshot = try JSONDecoder().decode(Event.Snapshot.self, from: data)

		hope(snapshot.id) == event.id
		hope(snapshot.description) == "test.one[1].more[two]"
		hope(snapshot.lemma) == "test.one.more"
		hope(snapshot.values["test.one"]?.int) == 1
		hope(snapshot.values["test.one.more"]?.string) == "two"
	}

	func test_Event_snapshot_encodes_Codable_payloads_as_JSON() throws {

		let payload = EventPayload(name: "lexicon", count: 2)
		let event = Event(test.one[payload])
		let value = try event.snapshot.values["test.one"].try()
		let decoded: EventPayload = try event[test.one]

		hope(value.object?["name"]?.string) == payload.name
		hope(value.object?["count"]?.int) == payload.count
		hope(decoded) == payload
	}

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
		hope(tickValues) == ["✅", "✅"]
		hope(allValues) == ["✅", "❌", "✅"]
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

	func test_Event_L_is_L() throws {
		hope(that: eventL.is(test)) == false
		hope(that: eventL.is(test.one)) == true
		hope(that: eventL.is(test.two)) == false
		hope(that: eventL.is(test.type.odd)) == false
	}

	func test_Event_L_is_I() throws {
		hope(that: eventL.is(I_test_one.self)) == true
		hope(that: eventL.l is I_test_one) == true
		hope(that: eventL.l is I_test_two) == false
		hope(that: eventL.l is I_test_type_odd) == true
	}

	func test_Event_L_is_any_I() throws {
		hope(that: eventL.is(test.one as I)) == true
		hope(that: eventL.is(test.two as I)) == false
		hope(that: eventL.is(test.one[4] as I)) == false
	}

	func test_Event_L_is_K() throws {
		hope(that: eventL.is(test.one[4])) == false
		hope(that: eventL.is(test.two[4])) == false
	}
}

extension SwiftLexicon™ {

	private var eventK: Event { Event(test.one[4].good) }

	func test_Event_K_is_L() throws {
		hope(that: eventK.is(test)) == false
		hope(that: eventK.is(test.one)) == false
		hope(that: eventK.is(test.one.good)) == true
		hope(that: eventK.is(test.type.odd.good)) == false
	}

	func test_Event_K_is_I() throws {
		hope(that: eventK.l is I_test) == false
		hope(that: eventK.l is I_test_one) == false
		hope(that: eventK.l is I_test_type_odd_good) == true
	}

	func test_Event_K_is_any_I() throws {
		hope(that: eventK.is(test.two.no.good as I)) == false
		hope(that: eventK.is(test.one.good as I)) == true
		hope(that: eventK.is(test.one[4] as I)) == false
		hope(that: eventK.is(test.one[2].good as I)) == false
		hope(that: eventK.is(test.one[4].good as I)) == true
		hope(that: eventK.is(test.type.odd[4].good as I)) == false
	}

	func test_Event_K_is_K() throws {
		hope(that: eventK.is(test.one[4])) == false
		hope(that: eventK.is(test.one[2].good)) == false
		hope(that: eventK.is(test.one[4].good)) == true
		hope(that: eventK.is(test.type.odd[4].good)) == false
	}
}
