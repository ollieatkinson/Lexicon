//
// github.com/screensailor 2022
//

import AsyncAlgorithms
import Foundation
import Synchronization

public final class Events: Sendable {

	private struct State: Sendable {
		var nextID: UInt64 = 0
		var channels: [UInt64: AsyncChannel<Event>] = [:]
		var delivery: Task<Void, Never>?
	}

	private let state = Mutex(State())

	public init() {}

	public var stream: AsyncStream<Event> {
		let channel = AsyncChannel<Event>()
		let id = insert(channel)
		return AsyncStream { continuation in
			let task = Task {
				for await event in channel {
					continuation.yield(event)
				}
				continuation.finish()
			}
			continuation.onTermination = { [weak self] _ in
				task.cancel()
				channel.finish()
				self?.remove(channel: id)
			}
		}
	}

	@discardableResult public func send(_ event: Event) -> Task<Void, Never> {
		state.withLock { state in
			let channels = Array(state.channels.values)
			let previous = state.delivery
			let delivery = Task {
				await previous?.value
				guard !Task.isCancelled else {
					return
				}
				for channel in channels {
					await channel.send(event)
				}
			}
			state.delivery = delivery
			return delivery
		}
	}

	public func finish() {
		let (channels, delivery) = state.withLock { state in
			defer { state.channels.removeAll() }
			let delivery = state.delivery
			state.delivery = nil
			return (Array(state.channels.values), delivery)
		}
		delivery?.cancel()
		for channel in channels {
			channel.finish()
		}
	}

	public func then(_ ƒ: @escaping @Sendable (Event) async -> Void) -> EventHandler {
		EventHandler(events: self, predicate: { _ in true }, action: ƒ)
	}

	public func subscribe(
		where predicate: @escaping @Sendable (Event) -> Bool = { _ in true },
		_ action: @escaping @Sendable (Event) async -> Void
	) -> EventSubscription {
		let channel = AsyncChannel<Event>()
		let id = insert(channel)
		let task = Task { [weak self] in
			defer {
				self?.remove(channel: id)
			}
			for await event in channel {
				guard !Task.isCancelled else {
					break
				}
				guard predicate(event) else {
					continue
				}
				await action(event)
			}
		}
		return EventSubscription(task) { [weak self] in
			self?.remove(channel: id)
			channel.finish()
		}
	}

	private func insert(_ channel: AsyncChannel<Event>) -> UInt64 {
		state.withLock { state in
			state.nextID += 1
			state.channels[state.nextID] = channel
			return state.nextID
		}
	}

	private func remove(channel id: UInt64) {
		state.withLock { state in
			_ = state.channels.removeValue(forKey: id)
		}
	}
}

public struct EventHandler: Sendable {
	public let events: Events
	public let predicate: @Sendable (Event) -> Bool
	public let action: @Sendable (Event) async -> Void

	public init(
		events: Events,
		predicate: @escaping @Sendable (Event) -> Bool,
		action: @escaping @Sendable (Event) async -> Void
	) {
		self.events = events
		self.predicate = predicate
		self.action = action
	}
}

public final class EventSubscription: Hashable, Sendable {
	private let task: Task<Void, Never>
	private let onCancel: @Sendable () -> Void

	public init(_ task: Task<Void, Never>, onCancel: @escaping @Sendable () -> Void = {}) {
		self.task = task
		self.onCancel = onCancel
	}

	deinit {
		cancel()
	}

	public func cancel() {
		onCancel()
		task.cancel()
	}

	public static func == (lhs: EventSubscription, rhs: EventSubscription) -> Bool {
		lhs === rhs
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}
}

private struct EventMatcher: Sendable {
	private let lemma: String
	private let values: [String: Event.Value]

	init(_ event: some I) {
		if let event = event as? any KProtocol {
			self.init(kProtocol: event)
		} else {
			self.init(lemma: event.__, values: [:])
		}
	}

	init<A: L>(k event: K<A>) {
		self.init(lemma: event(\.L).__, values: Dictionary(uniqueKeysWithValues: event.____.map { key, value in
			(key.__, Event.Value(value))
		}))
	}

	init(kProtocol event: any KProtocol) {
		self.init(lemma: event(\.L).__, values: Dictionary(uniqueKeysWithValues: event.____.map { key, value in
			(key.__, Event.Value(value))
		}))
	}

	private init(lemma: String, values: [String: Event.Value]) {
		self.lemma = lemma
		self.values = values
	}

	func matches(_ event: Event) -> Bool {
		event.l.__ == lemma && values.allSatisfy { key, value in
			event.values[key] == value
		}
	}
}

// MARK: send

public func >> (event: Event, publisher: Events) {
	publisher.send(event)
}

public func >> <A: L>(event: A, publisher: Events) {
	publisher.send(Event(event))
}

public func >> <A: L>(event: K<A>, publisher: Events) {
	publisher.send(Event(event))
}

// MARK: receive out of context

public func >> <A>(event: A.Type, handler: EventHandler) -> EventSubscription {
	handler.events.subscribe(where: { value in
		handler.predicate(value) && value.k(\.L) is A
	}, handler.action)
}

public func >> <A>(event: A, handler: EventHandler) -> EventSubscription where A: I {
	let matcher = EventMatcher(event)
	return handler.events.subscribe(where: { value in
		handler.predicate(value) && matcher.matches(value)
	}, handler.action)
}

public func >> <A>(event: K<A>, handler: EventHandler) -> EventSubscription where A: L {
	let matcher = EventMatcher(k: event)
	return handler.events.subscribe(where: { value in
		handler.predicate(value) && matcher.matches(value)
	}, handler.action)
}

// MARK: receive in context

public extension EventContext {

	func context(_ when: @escaping @Sendable (Self, Event) -> Bool) -> (@escaping @Sendable (Self, Event) async -> Void) -> EventContextHandler<Self> {
		{ [weak self] in
			EventContextHandler(
				object: self,
				events: self?.events,
				predicate: when,
				action: $0
			)
		}
	}

	func context(_ when: @escaping @Sendable (Self) -> Bool) -> (@escaping @Sendable (Self, Event) async -> Void) -> EventContextHandler<Self> {
		context { object, _ in when(object) }
	}

	func context() -> (@escaping @Sendable (Self, Event) async -> Void) -> EventContextHandler<Self> {
		context { _, _ in true }
	}
}

public struct EventContextHandler<Object: AnyObject & Sendable>: Sendable {
	public weak var object: Object?
	public let events: Events?
	public let predicate: @Sendable (Object, Event) -> Bool
	public let action: @Sendable (Object, Event) async -> Void
}

public func >> <O, A>(event: A.Type, handler: EventContextHandler<O>) -> EventSubscription
where O: AnyObject & Sendable
{
	handler.subscribe { value in
		value.k(\.L) is A
	}
}

public func >> <O, A>(event: A, handler: EventContextHandler<O>) -> EventSubscription
where A: I, O: AnyObject & Sendable
{
	let matcher = EventMatcher(event)
	return handler.subscribe { value in
		matcher.matches(value)
	}
}

public func >> <O, A>(event: K<A>, handler: EventContextHandler<O>) -> EventSubscription
where A: L, O: AnyObject & Sendable
{
	let matcher = EventMatcher(k: event)
	return handler.subscribe { value in
		matcher.matches(value)
	}
}

private extension EventContextHandler {

	func subscribe(_ matches: @escaping @Sendable (Event) -> Bool) -> EventSubscription {
		guard let events else {
			return EventSubscription(Task {})
		}
		return events.subscribe(where: { [weak object] event in
			guard let object else {
				return false
			}
			return predicate(object, event) && matches(event)
		}) { [weak object, action] event in
			guard let object else {
				return
			}
			await action(object, event)
		}
	}
}
