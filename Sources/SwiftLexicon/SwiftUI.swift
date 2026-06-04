//
// github.com/screensailor 2022
//

#if canImport(SwiftUI)
import SwiftUI

public extension EnvironmentValues {

	var events: Events {
		get { self[EventsKey.self] }
		set { self[EventsKey.self] = newValue }
	}

	private struct EventsKey: EnvironmentKey {
		static let defaultValue: Events = .init()
	}
}

public extension View {

	func events(_ events: Events) -> some View {
		environment(\.events, events)
	}

	func on<each Observed: I>(
		_ events: repeat each Observed,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		var matchers: [EventMatcher] = []
		for event in repeat each events {
			matchers.append(EventMatcher(event))
		}
		return modifier(OnEvents(request: EventObservationRequest(matchers), action: action))
	}

	func on<Observed: I>(
		_ events: [Observed],
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(request: EventObservationRequest(events.map(EventMatcher.init)), action: action))
	}

	func on<A>(
		_ type: A.Type,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(request: EventObservationRequest(type), action: action))
	}

	func on(
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(request: .all, action: action))
	}
}

private struct OnEvents: ViewModifier {

	@Environment(\.events) private var events
	private var action: EventAction

	let request: EventObservationRequest?

	init(
		request: EventObservationRequest?,
		action: @escaping @MainActor @Sendable (Event) -> Void
	) {
		self.request = request
		self.action = EventAction(action)
	}

	@ViewBuilder
	func body(content: Content) -> some View {
		if let request {
			let action = action.box
			content
				.task(id: TaskID(events: events, request: request)) {
					let observer = events.on(where: request.matches) { event in
						await action.perform(event)
					}
					await withTaskCancellationHandler {
						await observer.wait()
					} onCancel: {
						observer.cancel()
					}
				}
		} else {
			content
		}
	}

	private struct TaskID: Hashable {
		var events: ObjectIdentifier
		var request: EventObservationRequest.ID

		init(events: Events, request: EventObservationRequest) {
			self.events = events.id
			self.request = request.id
		}
	}
}

private struct EventAction: @MainActor DynamicProperty {

	@State fileprivate var box = Box()
	private let action: @MainActor @Sendable (Event) -> Void

	init(_ action: @escaping @MainActor @Sendable (Event) -> Void) {
		self.action = action
	}

	@MainActor mutating func update() {
		box.update(action)
	}

	@MainActor final class Box {
		private var action: @MainActor @Sendable (Event) -> Void = { _ in }

		func update(_ action: @escaping @MainActor @Sendable (Event) -> Void) {
			self.action = action
		}

		func perform(_ event: Event) {
			action(event)
		}
	}
}

private struct EventObservationRequest: Sendable {

	enum ID: Hashable, Sendable {
		case all
		case events([String])
		case type(ObjectIdentifier)
	}

	let id: ID
	let matches: @Sendable (Event) -> Bool

	static let all = EventObservationRequest(id: .all) { _ in true }

	init?(_ matchers: [EventMatcher]) {
		guard !matchers.isEmpty else {
			return nil
		}
		self.init(id: .events(matchers.map(\.id))) { event in
			matchers.contains { $0.matches(event) }
		}
	}

	init<A>(_ type: A.Type) {
		self.init(id: .type(ObjectIdentifier(type))) { event in
			event.is(type)
		}
	}

	private init(id: ID, matches: @escaping @Sendable (Event) -> Bool) {
		self.id = id
		self.matches = matches
	}
}

public extension View {

	func update<A: AnyObject, B>(_ a: A, _ k: ReferenceWritableKeyPath<A, B>, to b: B) -> Self {
		a[keyPath: k] = b
		return self
	}
}
#endif
