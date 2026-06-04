//
// github.com/screensailor 2026
//

#if canImport(SwiftUI)
import SwiftUI
import Testing
@testable import SwiftLexicon

@Suite
struct SwiftUISupportTests {

	@Test
	@MainActor
	func environment_events_can_be_injected() {
		let events = Events()
		var values = EnvironmentValues()

		values.events = events

		#expect(values.events === events)
	}

	@Test
	@MainActor
	func event_modifiers_accept_lexicon_values_and_types() {
		let events = Events()
		let view = EmptyView()
			.events(events)
			.on(test.one) { _ in }
			.on(test.one["value"], test.two) { _ in }
			.on(I_test_one.self) { _ in }
			.on { _ in }

		_ = view
	}
}
#endif
