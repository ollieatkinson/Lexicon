//
// github.com/screensailor 2026
//

import Foundation
import Testing
@testable import SwiftLexicon

@Suite
struct EventSubscriberTests {

	@Test
	func subscriber_delivers_matching_events() async throws {
		let events = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		defer {
			subscriber.cancel()
		}

		subscriber.subscribe(to: events)
		await events.send(Event(test.two)).value
		await events.send(Event(test.one)).value

		await log.wait(for: 1)

		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func subscriber_is_idempotent_when_subscribed_to_the_same_events() async throws {
		let events = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		defer {
			subscriber.cancel()
		}

		subscriber.subscribe(to: events)
		subscriber.subscribe(to: events)
		await events.send(Event(test.one)).value

		await log.wait(for: 1)

		#expect(subscriber.isSubscribed)
		#expect(await log.snapshot() == ["test.one"])
	}

	@Test
	func subscriber_resubscribes_to_new_events_and_cancels_the_old_subscription() async throws {
		let first = Events()
		let second = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		defer {
			subscriber.cancel()
		}

		subscriber.subscribe(to: first)
		await first.send(Event(test.one["initial"])).value
		await log.wait(for: 1)

		subscriber.subscribe(to: second)
		await first.send(Event(test.one["stale"])).value
		await second.send(Event(test.one["fresh"])).value

		await log.wait(for: 2)

		#expect(await log.snapshot() == ["test.one[initial]", "test.one[fresh]"])
	}

	@Test
	func subscriber_updates_its_handler_without_resubscribing() async throws {
		let events = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber()
		defer {
			subscriber.cancel()
		}

		subscriber.subscribe(to: events, where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		subscriber.update(where: { $0.is(test.two) }) { event in
			await log.append(event)
		}

		await events.send(Event(test.one)).value
		await events.send(Event(test.two)).value

		await log.wait(for: 1)

		#expect(await log.snapshot() == ["test.two"])
	}

	@Test
	func subscriber_cancel_stops_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}

		subscriber.subscribe(to: events)
		subscriber.cancel()
		await events.send(Event(test.one)).value

		#expect(!subscriber.isSubscribed)
		#expect(await log.snapshot().isEmpty)
	}

	@Test
	func subscriber_subscribe_to_nil_cancels_subscription() async throws {
		let events = Events()
		let log = EventLog()
		let subscriber = Events.Subscriber(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}

		subscriber.subscribe(to: events)
		subscriber.subscribe(to: nil)
		await events.send(Event(test.one)).value

		#expect(!subscriber.isSubscribed)
		#expect(await log.snapshot().isEmpty)
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
	func direct_subscription_filters_and_cancels_delivery() async throws {
		let events = Events()
		let log = EventLog()
		let subscription = events.subscribe(where: { $0.is(test.one) }) { event in
			await log.append(event)
		}
		defer {
			subscription.cancel()
			events.finish()
		}

		await events.send(Event(test.two)).value
		await events.send(Event(test.one["matched"])).value

		await log.wait(for: 1)
		#expect(await log.snapshot() == ["test.one[matched]"])

		subscription.cancel()
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
	func context_subscription_uses_weak_context_and_stops_after_context_deinitializes() async throws {
		let events = Events()
		let log = EventLog()
		let deinitSignal = DeinitSignal()
		var probe: EventContextProbe? = EventContextProbe(events: events, log: log, deinitSignal: deinitSignal)
		let weakProbe = WeakBox(probe)
		let makeHandler = try probe.require().context()
		let handler = makeHandler { object, event in
			await object.record(event)
		}
		let subscription = test.one >> handler
		defer {
			subscription.cancel()
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
