//
// github.com/screensailor 2022
//

import Foundation
import Synchronization

public final class Events: Identifiable, Sendable {

	private struct State: Sendable {
		var nextID: UInt64 = 0
		var sequence: UInt64 = 0
		var isFinished = false
		var continuations: [UInt64: AsyncStream<Event>.Continuation] = [:]
	}

	/// Controls how each observer buffers events while it is slower than the sender.
	public enum BufferingPolicy: Hashable, Sendable {
		/// Retain every pending event.
		case unbounded
		/// Retain the newest `capacity` events and drop the oldest pending event when full.
		case newest(Int)
		/// Retain the oldest `capacity` events and drop each newly sent event when full.
		case oldest(Int)
	}

	/// Describes how a synchronous send was handled by the current observers.
	public struct SendReceipt: Hashable, Sendable {
		/// The monotonically increasing sequence assigned to this accepted send.
		public let sequence: UInt64
		/// Observers whose continuation accepted without overflowing its buffer.
		public let enqueuedObservers: Int
		/// Observers whose buffer overflowed. `.oldest` rejected this event;
		/// `.newest` accepted it while displacing the oldest pending event.
		public let droppedObservers: Int
		/// Observers whose continuation had already terminated.
		public let terminatedObservers: Int

		public init(
			sequence: UInt64,
			enqueuedObservers: Int,
			droppedObservers: Int,
			terminatedObservers: Int
		) {
			self.sequence = sequence
			self.enqueuedObservers = enqueuedObservers
			self.droppedObservers = droppedObservers
			self.terminatedObservers = terminatedObservers
		}
	}

	public enum Error: Swift.Error, Equatable, Sendable, CustomStringConvertible {
		case invalidBufferCapacity(Int)
		case finished

		public var description: String {
			switch self {
			case .invalidBufferCapacity(let capacity):
				"Event buffer capacity must be positive, received \(capacity)."
			case .finished:
				"Cannot send an event after the event stream has finished."
			}
		}
	}

	private let bufferingPolicy: BufferingPolicy
	private let delivery = Mutex(())
	private let state = Mutex(State())

	/// Creates an event bus that retains the oldest 256 pending events per observer.
	public init() {
		self.bufferingPolicy = .oldest(256)
	}

	/// Creates an event bus with an explicit per-observer buffering policy.
	///
	/// Bounded policies require a positive capacity.
	public init(bufferingPolicy: BufferingPolicy) throws {
		switch bufferingPolicy {
		case .unbounded:
			break
		case .newest(let capacity), .oldest(let capacity):
			guard capacity > 0 else {
				throw Error.invalidBufferCapacity(capacity)
			}
		}
		self.bufferingPolicy = bufferingPolicy
	}

	deinit {
		finish()
	}

	public var id: ObjectIdentifier {
		ObjectIdentifier(self)
	}

	public var stream: AsyncStream<Event> {
		makeStream().stream
	}

	/// Publishes an event synchronously to every current observer.
	///
	/// Sends are serialized with other sends and ``finish()``. The returned receipt
	/// reports each continuation's yield result.
	@discardableResult public func send(_ event: Event) throws -> SendReceipt {
		try delivery.withLock { _ in
			let (sequence, continuations) = try state.withLock { state in
				guard !state.isFinished else {
					throw Error.finished
				}
				state.sequence += 1
				return (state.sequence, Array(state.continuations.values))
			}

			var enqueued = 0
			var dropped = 0
			var terminated = 0
			for continuation in continuations {
				switch continuation.yield(event) {
				case .enqueued:
					enqueued += 1
				case .dropped:
					dropped += 1
				case .terminated:
					terminated += 1
				@unknown default:
					terminated += 1
				}
			}
			return SendReceipt(
				sequence: sequence,
				enqueuedObservers: enqueued,
				droppedObservers: dropped,
				terminatedObservers: terminated
			)
		}
	}

	/// Closes the bus after all previously accepted events.
	///
	/// Buffered events remain available to observers before their streams end.
	/// The first call returns `true`; later calls return `false`.
	@discardableResult public func finish() -> Bool {
		delivery.withLock { _ in
			let continuations = state.withLock { state -> [AsyncStream<Event>.Continuation]? in
				guard !state.isFinished else {
					return nil
				}
				state.isFinished = true
				defer { state.continuations.removeAll() }
				return Array(state.continuations.values)
			}
			guard let continuations else {
				return false
			}
			for continuation in continuations {
				continuation.finish()
			}
			return true
		}
	}

	public func handler(_ ƒ: @escaping @Sendable (Event) async -> Void) -> EventHandler {
		EventHandler(events: self, predicate: { _ in true }, action: ƒ)
	}

	@discardableResult public func on(
		where predicate: @escaping @Sendable (Event) -> Bool = { _ in true },
		perform action: @escaping @Sendable (Event) async -> Void
	) -> Observer {
		let observation = makeStream()
		guard let observationID = observation.id else {
			return .finished()
		}
		let state = Observer.State()
		let task = Task { @concurrent [weak self] in
			defer {
				state.finish()
				self?.remove(continuation: observationID)
			}
			for await event in observation.stream {
				guard !Task.isCancelled else {
					break
				}
				guard predicate(event) else {
					continue
				}
				await action(event)
			}
		}
		return Observer(task, state: state) { [weak self] in
			self?.remove(continuation: observationID)
			observation.continuation.finish()
		}
	}

	private func makeStream() -> (
		id: UInt64?,
		stream: AsyncStream<Event>,
		continuation: AsyncStream<Event>.Continuation
	) {
		let stream = AsyncStream<Event>.makeStream(bufferingPolicy: bufferingPolicy.asyncStreamPolicy)
		guard let id = insert(stream.continuation) else {
			stream.continuation.finish()
			return (nil, stream.stream, stream.continuation)
		}
		stream.continuation.onTermination = { [weak self] _ in
			self?.remove(continuation: id)
		}
		return (id, stream.stream, stream.continuation)
	}

	private func insert(_ continuation: AsyncStream<Event>.Continuation) -> UInt64? {
		state.withLock { state in
			guard !state.isFinished else {
				return nil
			}
			state.nextID += 1
			state.continuations[state.nextID] = continuation
			return state.nextID
		}
	}

	private func remove(continuation id: UInt64) {
		state.withLock { state in
			_ = state.continuations.removeValue(forKey: id)
		}
	}
}

private extension Events.BufferingPolicy {
	var asyncStreamPolicy: AsyncStream<Event>.Continuation.BufferingPolicy {
		switch self {
		case .unbounded:
			.unbounded
		case .newest(let capacity):
			.bufferingNewest(capacity)
		case .oldest(let capacity):
			.bufferingOldest(capacity)
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

public extension Events {

	final class Observer: Hashable, Sendable {
		fileprivate final class State: Sendable {
			private let isObserving: Mutex<Bool>

			init(isObserving: Bool = true) {
				self.isObserving = Mutex(isObserving)
			}

			var value: Bool {
				isObserving.withLock { $0 }
			}

			func cancel() -> Bool {
				isObserving.withLock { isObserving in
					guard isObserving else {
						return false
					}
					isObserving = false
					return true
				}
			}

			func finish() {
				isObserving.withLock { $0 = false }
			}
		}

		private let task: Task<Void, Never>
		private let onCancel: @Sendable () -> Void
		private let state: State

		public init(_ task: Task<Void, Never>, onCancel: @escaping @Sendable () -> Void = {}) {
			let state = State()
			self.task = task
			self.state = state
			self.onCancel = onCancel
			Task {
				await task.value
				state.finish()
			}
		}

		fileprivate init(_ task: Task<Void, Never>, state: State, onCancel: @escaping @Sendable () -> Void = {}) {
			self.task = task
			self.state = state
			self.onCancel = onCancel
		}

		deinit {
			cancel()
		}

		public var isObserving: Bool {
			state.value
		}

		public func cancel() {
			guard state.cancel() else {
				return
			}
			onCancel()
			task.cancel()
		}

		public func wait() async {
			await task.value
			state.finish()
		}

		public static func == (lhs: Observer, rhs: Observer) -> Bool {
			lhs === rhs
		}

		public func hash(into hasher: inout Hasher) {
			hasher.combine(ObjectIdentifier(self))
		}

		fileprivate static func finished() -> Observer {
			Observer(Task {}, state: State(isObserving: false))
		}
	}
}

public typealias EventObserver = Events.Observer

struct EventMatcher: Sendable {
	let id: String
	private let lemma: String
	private let values: [String: Event.Value]

	init(_ event: some I) {
		if let event = event as? any KProtocol {
			self.init(kProtocol: event)
		} else {
			self.init(id: event.__, lemma: event.__, values: [:])
		}
	}

	init<A: L>(k event: K<A>) {
		self.init(id: event.__, lemma: event(\.L).__, values: Dictionary(uniqueKeysWithValues: event.____.map { key, value in
			(key.__, value)
		}))
	}

	init(kProtocol event: any KProtocol) {
		self.init(id: event.__, lemma: event(\.L).__, values: Dictionary(uniqueKeysWithValues: event.____.map { key, value in
			(key.__, value)
		}))
	}

	private init(id: String, lemma: String, values: [String: Event.Value]) {
		self.id = id
		self.lemma = lemma
		self.values = values
	}

	func matches(_ event: Event) -> Bool {
		event.l.__ == lemma && values.allSatisfy { key, value in
			event.values[key] == value
		}
	}
}

public extension Events {

	@discardableResult func on(
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		on(where: { _ in true }, perform: action)
	}

	@discardableResult func on<A>(
		_ type: A.Type,
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		on(where: { event in
			event.matches(type)
		}, perform: action)
	}

	@discardableResult func on(
		_ event: some I,
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		let matcher = EventMatcher(event)
		return on(where: matcher.matches, perform: action)
	}

	@discardableResult func on<each Observed: I>(
		_ events: repeat each Observed,
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		var matchers: [EventMatcher] = []
		for event in repeat each events {
			matchers.append(EventMatcher(event))
		}
		return observe(matchers, perform: action)
	}

	@discardableResult func on<Observed: I>(
		_ events: [Observed],
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		let matchers = events.map(EventMatcher.init)
		return observe(matchers, perform: action)
	}

	private func observe(
		_ matchers: [EventMatcher],
		perform action: @escaping @Sendable (Event) async -> Void
	) -> EventObserver {
		guard !matchers.isEmpty else {
			return .finished()
		}
		return on(where: { event in
			matchers.contains { $0.matches(event) }
		}, perform: action)
	}
}

// MARK: receive out of context

@discardableResult public func >> <A>(event: A.Type, handler: EventHandler) -> EventObserver {
	handler.events.on(where: { value in
		handler.predicate(value) && value.k(\.L) is A
	}, perform: handler.action)
}

@discardableResult public func >> <A>(event: A, handler: EventHandler) -> EventObserver where A: I {
	let matcher = EventMatcher(event)
	return handler.events.on(where: { value in
		handler.predicate(value) && matcher.matches(value)
	}, perform: handler.action)
}

@discardableResult public func >> <A>(event: K<A>, handler: EventHandler) -> EventObserver where A: L {
	let matcher = EventMatcher(k: event)
	return handler.events.on(where: { value in
		handler.predicate(value) && matcher.matches(value)
	}, perform: handler.action)
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

@discardableResult public func >> <O, A>(event: A.Type, handler: EventContextHandler<O>) -> EventObserver
where O: AnyObject & Sendable
{
	handler.observe { value in
		value.k(\.L) is A
	}
}

@discardableResult public func >> <O, A>(event: A, handler: EventContextHandler<O>) -> EventObserver
where A: I, O: AnyObject & Sendable
{
	let matcher = EventMatcher(event)
	return handler.observe { value in
		matcher.matches(value)
	}
}

@discardableResult public func >> <O, A>(event: K<A>, handler: EventContextHandler<O>) -> EventObserver
where A: L, O: AnyObject & Sendable
{
	let matcher = EventMatcher(k: event)
	return handler.observe { value in
		matcher.matches(value)
	}
}

private extension EventContextHandler {

	func observe(_ matches: @escaping @Sendable (Event) -> Bool) -> EventObserver {
		guard let events else {
			return .finished()
		}
		return events.on(where: { [weak object] event in
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
