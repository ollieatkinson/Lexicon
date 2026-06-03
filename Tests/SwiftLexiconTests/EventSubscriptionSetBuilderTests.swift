//
// github.com/screensailor 2026
//

import Testing
@testable import SwiftLexicon

@Suite
struct EventSubscriptionSetBuilderTests {

	@Test
	func builder_collects_subscription_control_flow() {
		let subscriptions = subscriptions(includeOptional: true)
		defer {
			subscriptions.forEach { $0.cancel() }
		}

		#expect(subscriptions.count == 4)
	}

	@Test
	func builder_omits_unmatched_optional_branch() {
		let subscriptions = subscriptions(includeOptional: false)
		defer {
			subscriptions.forEach { $0.cancel() }
		}

		#expect(subscriptions.count == 3)
	}
}

@Bear private func subscriptions(includeOptional: Bool) -> Mind {
	EventSubscription(Task {})
	if includeOptional {
		EventSubscription(Task {})
	}
	for _ in 0..<2 {
		EventSubscription(Task {})
	}
}
