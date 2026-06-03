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

	func onEvent(
		_ event: some I,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(predicate: { $0.is(event) }, action: action))
	}

	func onEvent<A>(
		_ type: A.Type,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(predicate: { $0.is(type) }, action: action))
	}

	func onEvents(
		_ events: any I...,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		onEvents(events, perform: action)
	}

	func onEvents(
		_ events: [any I],
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(isEnabled: !events.isEmpty, predicate: { event in
			events.contains(where: event.is)
		}, action: action))
	}

	func onEvents(
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(predicate: { _ in true }, action: action))
	}

	func onEvents(
		where predicate: @escaping @Sendable (Event) -> Bool,
		perform action: @escaping @MainActor @Sendable (Event) -> Void
	) -> some View {
		modifier(OnEvents(predicate: predicate, action: action))
	}

	@available(*, deprecated, renamed: "onEvents(_:perform:)")
	func on(_ events: any I..., ƒ: @escaping @MainActor @Sendable (Event) -> Void) -> some View {
		onEvents(events, perform: ƒ)
	}
}

private struct OnEvents: ViewModifier {

	@Environment(\.events) private var events
	@State private var subscriber = Events.Subscriber()

	var isEnabled = true
	let predicate: @Sendable (Event) -> Bool
	let action: @MainActor @Sendable (Event) -> Void

	func body(content: Content) -> some View {
		// Keep the retained subscriber using the latest closures without
		// forcing a resubscribe on every render.
		subscriber.update(where: predicate) { event in
			await action(event)
		}

		return content
			.onAppear {
				updateSubscriber()
			}
			.onChange(of: events.id, initial: true) { _, _ in
				updateSubscriber()
			}
			.onChange(of: isEnabled, initial: false) { _, _ in
				updateSubscriber()
			}
			.onDisappear {
				subscriber.cancel()
			}
	}

	private func updateSubscriber() {
		if isEnabled {
			subscriber.subscribe(to: events)
		} else {
			subscriber.cancel()
		}
	}
}

public extension View {

	func update<A: AnyObject, B>(_ a: A, _ k: ReferenceWritableKeyPath<A, B>, to b: B) -> Self {
		a[keyPath: k] = b
		return self
	}
}
#endif
