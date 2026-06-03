//
// github.com/screensailor 2021
//

import Testing
import Foundation
@testable import Lexicon
import SwiftLexicon

@Suite

struct CLI™ {

	@Test
	func test_against_session_record() async throws {

		let session: CLI.Session = try "testCLI".json()
		let expectations = try session.replayExpectations()

		try await withThrowingTaskGroup(of: Void.self) { group in
			for expectation in expectations {
				group.addTask {
					try await expectation.replay(video: session.video)
				}
			}
			try await group.waitForAll()
		}
	}
}

private struct CLIReplayExpectation: Sendable {
	var action: CLI.Session.Event
	var expected: CLI.Session.Event
}

private enum CLIReplayEvent: Sendable {
	case action(Action, EventDetail)
	case didChange
	case ignored

	enum Action: String, Sendable {
		case append = "app.event.cli.append"
		case backspace = "app.event.cli.backspace"
		case enter = "app.event.cli.enter"
		case selectNext = "app.event.cli.select.next"
		case selectPrevious = "app.event.cli.select.previous"
	}

	init(_ event: CLI.Session.Event) throws {
		let detail = try EventDetail(bracketed: event.description)
		if let action = Action(rawValue: detail.id) {
			self = .action(action, detail)
		} else if detail.id == "app.event.cli.did.change" {
			self = .didChange
		} else {
			self = .ignored
		}
	}
}

private extension CLI.Session {

	func replayExpectations() throws -> [CLIReplayExpectation] {
		var pending: CLI.Session.Event?
		var expectations: [CLIReplayExpectation] = []

		for event in events {
			switch try CLIReplayEvent(event) {
			case .action:
				pending = event
			case .didChange:
				if let action = pending {
					expectations.append(.init(action: action, expected: event))
					pending = nil
				}
			case .ignored:
				break
			}
		}

		return expectations
	}
}

private extension CLIReplayExpectation {

	func replay(video: CLI.Session.Video?) async throws {
		var cli = try await action.cli()
		let event = try CLIReplayEvent(action)
		guard case .action(let action, let detail) = event else {
			throw LexiconError("unexpected test event")
		}

		try await cli.apply(action, detail: detail)
		let record = await cli.record()
		guard record == expected.record else {
			throw try failureError(actual: record, video: video)
		}
	}

	func failureError(actual: CLI.Session.Record, video: CLI.Session.Video?) throws -> LexiconError {
		let video = video.flatMap { o in
			o.url.absoluteString + "?t=\(Int(o.start + action.time))\n"
		} ?? ""
		return try LexiconError("""

						🐞 Failed \(action):
						\(video)
						• EVENT:
						\(action.json().string())

						• EXPECTED:
						\(expected.json().string())

						• ACTUAL:
						\(actual.json().string())
						""")
	}
}

private extension CLI {

	mutating func apply(_ action: CLIReplayEvent.Action, detail: EventDetail) async throws {
		switch action {
		case .append:
			let character = try detail.data[action.rawValue].try().string.try().first.try()
			await append(character)
		case .backspace:
			await backspace()
		case .enter:
			await enter()
		case .selectNext:
			selectNext()
		case .selectPrevious:
			selectPrevious()
		}
	}
}
