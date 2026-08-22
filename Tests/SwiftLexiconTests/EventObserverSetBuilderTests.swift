//
// github.com/screensailor 2026
//

import Testing
@testable import SwiftLexicon

@Suite
struct EventObserverSetBuilderTests {

	@Test
	func builder_collects_observer_control_flow() {
		let observers = observers(includeOptional: true)
		defer {
			observers.forEach { $0.cancel() }
		}

		#expect(observers.count == 4)
	}

	@Test
	func builder_omits_unmatched_optional_branch() {
		let observers = observers(includeOptional: false)
		defer {
			observers.forEach { $0.cancel() }
		}

		#expect(observers.count == 3)
	}
}

@Bear private func observers(includeOptional: Bool) -> Mind {
	EventObserver(Task {})
	if includeOptional {
		EventObserver(Task {})
	}
	for _ in 0..<2 {
		EventObserver(Task {})
	}
}
