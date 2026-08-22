//
// github.com/screensailor 2026
//

import Foundation
import Synchronization
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

		try events.send(Event(test.two))
		try events.send(Event(test.one))

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

		try events.send(Event(test.one["skipped"]))
		try events.send(Event(test.one["matched"]))

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

		try events.send(Event(test.two))
		try events.send(Event(test.one))
		try events.send(Event(test.one.more))

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

		try events.send(Event(test.two["skipped"]))
		try events.send(Event(test.one))
		try events.send(Event(test.two["matched"]))

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

		try events.send(Event(test.one))
		try events.send(Event(test.two))

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

		try events.send(Event(test.one))

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

		try events.send(Event(test.one))
		await log.wait(for: 1)

		events.finish()
		await observer.wait()

		#expect(!observer.isObserving)
		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func manually_constructed_observer_wait_updates_state() async {
		let observer = Events.Observer(Task {})

		await observer.wait()

		#expect(!observer.isObserving)
	}

	@Test
	func observing_a_finished_bus_is_immediately_terminal() {
		let events = Events()
		events.finish()

		let observer = events.on { _ in
			Issue.record("A finished event bus must not deliver events.")
		}

		#expect(!observer.isObserving)
	}

	@Test
	func observer_cancel_stops_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(test.one) { event in
			await log.append(event)
		}

		observer.cancel()
		try events.send(Event(test.one))

		#expect(!observer.isObserving)
		#expect(await log.snapshot().isEmpty)
	}

	@Test
	func observer_where_filters_and_cancels_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let observer = events.on(where: { $0.matches(test.one) }) { event in
			await log.append(event)
		}
		defer {
			observer.cancel()
			events.finish()
		}

		try events.send(Event(test.two))
		try events.send(Event(test.one["matched"]))

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one[matched]"])

		observer.cancel()
		try events.send(Event(test.one["stale"]))

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
		try events.send(one)
		try events.send(two)

		#expect(await first.value.map(\.id) == [one.id, two.id])
		#expect(await second.value.map(\.id) == [one.id, two.id])

		let finishingStream = events.stream
		let finished = Task {
			await collectUntilFinished(from: finishingStream)
		}
		let final = Event(test.one.more)
		try events.send(final)
		events.finish()

		#expect(await finished.value.map(\.id) == [final.id])
	}

	@Test
	func finish_drains_buffered_events_and_is_terminal() async throws {
		let events = try Events(bufferingPolicy: .oldest(2))
		let stream = events.stream
		let first = Event(test.one)
		let second = Event(test.two)

		_ = try events.send(first)
		_ = try events.send(second)

		#expect(events.finish())
		#expect(!events.finish())
		#expect(await collectUntilFinished(from: stream).map(\.id) == [first.id, second.id])
		#expect(throws: Events.Error.finished) {
			try events.send(Event(test.one.more))
		}
	}

	@Test
	func bounded_buffer_reports_drops_and_applies_retention_policy() async throws {
		let oldest = try Events(bufferingPolicy: .oldest(1))
		let oldestStream = oldest.stream
		let first = Event(test.one)
		let second = Event(test.two)

		let firstReceipt = try oldest.send(first)
		let oldestDrop = try oldest.send(second)
		oldest.finish()

		#expect(firstReceipt.sequence == 1)
		#expect(firstReceipt.enqueuedObservers == 1)
		#expect(oldestDrop.sequence == 2)
		#expect(oldestDrop.droppedObservers == 1)
		#expect(await collectUntilFinished(from: oldestStream).map(\.id) == [first.id])

		let newest = try Events(bufferingPolicy: .newest(1))
		let newestStream = newest.stream
		_ = try newest.send(first)
		let newestDrop = try newest.send(second)
		newest.finish()

		#expect(newestDrop.droppedObservers == 1)
		#expect(await collectUntilFinished(from: newestStream).map(\.id) == [second.id])
	}

	@Test
	func bounded_buffer_rejects_nonpositive_capacity() {
		#expect(throws: Events.Error.invalidBufferCapacity(0)) {
			try Events(bufferingPolicy: .oldest(0))
		}
		#expect(throws: Events.Error.invalidBufferCapacity(-1)) {
			try Events(bufferingPolicy: .newest(-1))
		}
	}

	@Test
	func explicit_matching_preserves_event_identity() {
		let event = Event(test.one[4].good)
		let id = event.id

		#expect(event.matches(test.one[4].good))
		#expect(event.matches(I_test_type_odd_good.self))
		#expect(event.id == id)
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

		try events.send(Event(test.two))
		try events.send(Event(test.one["matched"]))

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one[matched]"])

		observer.cancel()
		try events.send(Event(test.one["stale"]))

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
		try events.send(Event(test.one))
		try events.send(Event(test.one["indexed"]))
		try events.send(explicit)

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

		try events.send(Event(test.two))
		try events.send(Event(test.one))

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one"])

		probe = nil
		await deinitSignal.wait()
		#expect(weakProbe.value == nil)

		try events.send(Event(test.one))

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

@MainActor private final class EventContextProbe: EventContext {

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

private final class DeinitSignal: Sendable {

	private struct State: Sendable {
		var didSignal = false
		var continuations: [CheckedContinuation<Void, Never>] = []
	}

	private let state = Mutex(State())

	func signal() {
		let pending = state.withLock { state in
			state.didSignal = true
			defer { state.continuations.removeAll() }
			return state.continuations
		}

		for continuation in pending {
			continuation.resume()
		}
	}

	func wait() async {
		await withCheckedContinuation { continuation in
			let shouldResume = state.withLock { state in
				if state.didSignal {
					return true
				}
				state.continuations.append(continuation)
				return false
			}
			if shouldResume {
				continuation.resume()
			}
		}
	}
}
