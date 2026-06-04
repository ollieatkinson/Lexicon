//
// github.com/screensailor 2026
//

import Foundation
import Testing
@testable import SwiftLexicon

@Suite
struct EventObserverTests {

	@Test
	func observer_delivers_matching_events() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one)).value

		await log.wait(for: 1)

		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func observer_matches_bracketed_event_values() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one["matched"]) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.one["skipped"])).value
		await events.send(Event(test.one["matched"])).value

		await log.wait(for: 1)

		#expect(observer.isObserving)
		#expect(await log.snapshot() == ["test.one[matched]"])
	}

	@Test
	func matcher_identity_includes_bracketed_event_values() {
		#expect(EventMatcher(test.one["old"]).id == "test.one[old]")
		#expect(EventMatcher(test.one["new"]).id == "test.one[new]")
	}

	@Test
	func observer_matches_event_types() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(I_test_one.self) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one)).value
		await events.send(Event(test.one.more)).value

		await log.wait(for: 1)

		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func observer_matches_any_listed_event() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one, test.two["matched"]) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two["skipped"])).value
		await events.send(Event(test.one)).value
		await events.send(Event(test.two["matched"])).value

		await log.wait(for: 2)

		#expect(await log.snapshot() == ["test.one", "test.two[matched]"])
	}

	@Test
	func observer_can_listen_to_all_events() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		test.one >> events
		test.two >> events

		await log.wait(for: 2)

		#expect(await log.snapshot() == ["test.one", "test.two"])
	}

	@Test
	func observer_with_empty_event_list_is_a_noop() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on([L_test_one]()) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.one)).value

		#expect(!observer.isObserving)
		#expect(await log.snapshot().isEmpty)
	}

	@Test
	func observer_wait_completes_when_events_finish() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.one)).value
		await log.wait(for: 1)

		events.finish()
		await observer.wait()

		#expect(!observer.isObserving)
		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func observer_cancel_stops_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one) { event in
			await log.append(event)
		}

		observer.cancel()
		await events.send(Event(test.one)).value

		#expect(!observer.isObserving)
		#expect(await log.snapshot().isEmpty)
	}

	@Test
	func observer_where_filters_and_cancels_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one["matched"])).value

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one[matched]"])

		observer.cancel()
		await events.send(Event(test.one["stale"])).value

		#expect(await log.snapshot() == ["test.one[matched]"])
	}

	@Test
	func streams_each_receive_each_event_once_and_finish() async throws {
		let events = Events()
		let firstStream = events.stream
		let secondStream = events.stream
		let first = Task {
			await collect(2, from: firstStream)
		}
		let second = Task {
			await collect(2, from: secondStream)
		}
		defer {
			first.cancel()
			second.cancel()
			events.finish()
		}

		let one = Event(test.one)
		let two = Event(test.two)
		await events.send(one).value
		await events.send(two).value

		#expect(await first.value.map(\.id) == [one.id, two.id])
		#expect(await second.value.map(\.id) == [one.id, two.id])

		let finishingStream = events.stream
		let finished = Task {
			await collectUntilFinished(from: finishingStream)
		}
		let final = Event(test.one.more)
		await events.send(final).value
		events.finish()

		#expect(await finished.value.map(\.id) == [final.id])
	}

	@Test
	func handler_operator_observes_matching_events() async throws {
		let events = Events()
		let log = EventLog()
		let observer = test.one >> events.handler { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one["matched"])).value

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one[matched]"])

		observer.cancel()
		await events.send(Event(test.one["stale"])).value

		#expect(await log.snapshot() == ["test.one[matched]"])
	}

	@Test
	func send_operators_publish_lemma_k_and_existing_event_values() async throws {
		let events = Events()
		let stream = events.stream
		let collected = Task {
			await collect(3, from: stream)
		}
		defer {
			collected.cancel()
			events.finish()
		}

		let explicit = Event(test.two["explicit"])
		test.one >> events
		test.one["indexed"] >> events
		explicit >> events

		#expect(await collected.value.map(\.description) == [
			"test.one",
			"test.one[indexed]",
			"test.two[explicit]",
		])
	}

	@Test @MainActor
	func context_observer_uses_weak_context_and_stops_after_context_deinitializes() async throws {
		let events = Events()
		let log = EventLog()
		let deinitSignal = DeinitSignal()
		var probe: EventContextProbe? = EventContextProbe(events: events, log: log, deinitSignal: deinitSignal)
		let weakProbe = WeakBox(probe)
		let makeHandler = try probe.require().context()
		let handler = makeHandler { object, event in
			await object.record(event)
		}
		let observer = test.one >> handler
		defer {
			observer.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one)).value

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one"])

		probe = nil
		await deinitSignal.wait()
		#expect(weakProbe.value == nil)

		await events.send(Event(test.one)).value

		#expect(await log.snapshot() == ["test.one"])
	}
}

private actor EventLog {

	private struct Waiter {
		var count: Int
		var continuation: CheckedContinuation<Void, Never>
	}

	private var descriptions: [String] = []
	private var waiters: [Waiter] = []

	func append(_ event: Event) {
		descriptions.append(event.description)
		resumeReadyWaiters()
	}

	func wait(for count: Int) async {
		if descriptions.count >= count {
			return
		}
		await withCheckedContinuation { continuation in
			waiters.append(Waiter(count: count, continuation: continuation))
		}
	}

	func snapshot() -> [String] {
		descriptions
	}

	private func resumeReadyWaiters() {
		let ready = waiters.filter { descriptions.count >= $0.count }
		waiters.removeAll { descriptions.count >= $0.count }
		for waiter in ready {
			waiter.continuation.resume()
		}
	}
}

private func collect(_ count: Int, from stream: AsyncStream<Event>) async -> [Event] {
	var events: [Event] = []
	for await event in stream {
		events.append(event)
		if events.count == count {
			break
		}
	}
	return events
}

private func collectUntilFinished(from stream: AsyncStream<Event>) async -> [Event] {
	var events: [Event] = []
	for await event in stream {
		events.append(event)
	}
	return events
}

@MainActor private final class EventContextProbe: EventContext, @unchecked Sendable {

	let events: Events
	private let log: EventLog
	private let deinitSignal: DeinitSignal

	init(events: Events, log: EventLog, deinitSignal: DeinitSignal) {
		self.events = events
		self.log = log
		self.deinitSignal = deinitSignal
	}

	deinit {
		deinitSignal.signal()
	}

	nonisolated var description: String {
		"EventContextProbe"
	}

	func record(_ event: Event) async {
		await log.append(event)
	}
}

private extension Optional {

	func require() throws -> Wrapped {
		try #require(self)
	}
}

private final class WeakBox<Value: AnyObject> {

	weak var value: Value?

	init(_ value: Value?) {
		self.value = value
	}
}

private final class DeinitSignal: @unchecked Sendable {

	private let lock = NSLock()
	private var didSignal = false
	private var continuations: [CheckedContinuation<Void, Never>] = []

	func signal() {
		lock.lock()
		didSignal = true
		let pending = continuations
		continuations.removeAll()
		lock.unlock()

		for continuation in pending {
			continuation.resume()
		}
	}

	func wait() async {
		await withCheckedContinuation { continuation in
			lock.lock()
			if didSignal {
				lock.unlock()
				continuation.resume()
			} else {
				continuations.append(continuation)
				lock.unlock()
			}
		}
	}
}
