//
// github.com/screensailor 2026
//

import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite
struct LexiconLSPCommandTests {

	@Test
	func test_process_answers_initialize_before_stdin_closes() throws {
		let directory = try TemporaryDirectory()
		try directory.write("lexicon-lsp.json", #"{"lexicon":"demo.lexicon"}"#)
		try directory.write("demo.lexicon", Self.lexicon)

		var server = try LSPProcess()
		defer { server.stop() }
		try server.initialize(root: directory.url)
		let response = try server.response(id: 1)

		#expect(response["result"] != nil)
	}

	@Test
	func test_process_completes_paths_from_workspace_configuration() throws {
		let directory = try TemporaryDirectory()
		try directory.write("lexicon-lsp.json", #"{"lexicon":"demo.lexicon"}"#)
		try directory.write("demo.lexicon", Self.lexicon)
		let sourceURL = directory.url.appendingPathComponent("demo.rs")
		let source = "fn main() { let complete = l!(test.type.even.); }"

		var server = try LSPProcess()
		defer { server.stop() }
		try server.initialize(root: directory.url)
		try server.didOpen(uri: sourceURL, languageID: "rust", text: source)
		try server.completion(id: 2, uri: sourceURL, in: source, after: "fn main() { let complete = l!(test.type.even.")

		let messages = try server.finish()
		let response = try #require(messages.response(id: 2))

		#expect(response.completionLabels == ["bad", "no"])
	}

	@Test
	func test_process_recomposes_imported_open_lexicon_documents() throws {
		let directory = try TemporaryDirectory()
		try directory.write("lexicon-lsp.json", #"{"lexicon":"root.lexicon"}"#)
		try directory.write("root.lexicon", "@ shared.lexicon\ntest:")
		try directory.write("shared.lexicon", """
		shared:
			type:
				even:
					bad:
		""")
		let sourceURL = directory.url.appendingPathComponent("demo.rs")
		let sharedURL = directory.url.appendingPathComponent("shared.lexicon")
		let source = "fn main() { let complete = l!(test.type.even.); }"

		var server = try LSPProcess()
		defer { server.stop() }
		try server.initialize(root: directory.url)
		try server.didOpen(uri: sourceURL, languageID: "rust", text: source)
		try server.completion(id: 2, uri: sourceURL, in: source, after: "fn main() { let complete = l!(test.type.even.")

		try server.didOpen(uri: sharedURL, languageID: "lexicon", text: """
		shared:
			type:
				even:
					bad:
					good:
		""")

		try server.completion(id: 3, uri: sourceURL, in: source, after: "fn main() { let complete = l!(test.type.even.")
		let messages = try server.finish()

		#expect(try #require(messages.response(id: 2)).completionLabels == ["bad"])
		#expect(try #require(messages.response(id: 3)).completionLabels == ["bad", "good"])
	}

	@Test
	func test_process_reports_configuration_and_request_errors() throws {
		let directory = try TemporaryDirectory()
		let configURL = directory.url.appendingPathComponent("lexicon-lsp.json")
		try directory.write("lexicon-lsp.json", #"{"lexicon":"missing.lexicon"}"#)

		var server = try LSPProcess()
		defer { server.stop() }
		try server.initialize(root: directory.url)
		try server.didOpen(uri: configURL, languageID: "json", text: #"{"lexicon":"missing.lexicon"}"#)
		try server.sendBody(Data("{".utf8))
		try server.send([
			"jsonrpc": "2.0",
			"id": 98,
			"method": "textDocument/completion",
			"params": [
				"textDocument": ["uri": configURL.absoluteString],
				"position": [:],
			],
		])
		let messages = try server.finish()

		#expect(messages.diagnostics(uri: configURL).contains { $0.contains("Could not load Lexicon index") })
		#expect(messages.contains { $0.errorCode == -32600 })
		#expect(messages.response(id: 98)?.errorCode == -32602)
	}

	@Test
	func test_process_discovers_subdirectory_configuration() throws {
		let directory = try TemporaryDirectory()
		let app = directory.url.appendingPathComponent("app", isDirectory: true)
		try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
		try Data(#"{"lexicon":"app.lexicon"}"#.utf8).write(to: app.appendingPathComponent(".lexicon.conf"))
		try Data(Self.lexicon.utf8).write(to: app.appendingPathComponent("app.lexicon"))
		let sourceURL = app.appendingPathComponent("demo.go")
		let source = #"var complete = l("test.type.even.")"#

		var server = try LSPProcess()
		defer { server.stop() }
		try server.initialize(root: directory.url)
		try server.didOpen(uri: sourceURL, languageID: "go", text: source)
		try server.completion(id: 2, uri: sourceURL, in: source, after: #"var complete = l("test.type.even."#)

		let messages = try server.finish()
		let response = try #require(messages.response(id: 2))

		#expect(response.completionLabels == ["bad", "no"])
	}

	private static let lexicon = """
	test:
		type:
			even:
				bad:
				no:
	"""
}

private struct LSPProcess {
	private let process: Process
	private let input: Pipe
	private let output: Pipe
	private let error: Pipe
	private let outputFileDescriptorFlags: Int32
	private var outputBuffer = Data()
	private var finished = false

	init() throws {
		process = Process()
		input = Pipe()
		output = Pipe()
		error = Pipe()
		guard let outputFileDescriptorFlags = Self.enableNonblockingReads(for: output.fileHandleForReading) else {
			throw "Could not enable nonblocking reads for lexicon-lsp stdout"
		}
		self.outputFileDescriptorFlags = outputFileDescriptorFlags
		process.executableURL = Self.packageRoot().appendingPathComponent(".build/debug/lexicon-lsp")
		process.standardInput = input
		process.standardOutput = output
		process.standardError = error
		try process.run()
	}

	mutating func stop() {
		guard finished == false else {
			return
		}
		_ = try? finish()
	}

	mutating func finish() throws -> [[String: Any]] {
		guard finished == false else {
			return []
		}
		try send([
			"jsonrpc": "2.0",
			"method": "exit",
		])
		try input.fileHandleForWriting.close()
		process.waitUntilExit()
		finished = true
		restoreBlockingReads()
		readAvailableOutput()
		let data = outputBuffer
		let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		guard process.terminationStatus == 0 else {
			throw "lexicon-lsp exited with \(process.terminationStatus).\n\(stderr)"
		}
		return try Self.messages(in: data)
	}

	mutating func initialize(root: URL) throws {
		try send([
			"jsonrpc": "2.0",
			"id": 1,
			"method": "initialize",
			"params": [
				"rootUri": root.absoluteString,
				"workspaceFolders": [
					[
						"uri": root.absoluteString,
						"name": root.lastPathComponent,
					],
				],
			],
		])
	}

	mutating func response(id: Int, timeout: TimeInterval = 5) throws -> [String: Any] {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			readAvailableOutput()
			if let response = try Self.messages(in: outputBuffer).response(id: id) {
				return response
			}
			Thread.sleep(forTimeInterval: 0.01)
		}
		throw "Timed out waiting for lexicon-lsp response \(id)"
	}

	func didOpen(uri: URL, languageID: String, text: String) throws {
		try send([
			"jsonrpc": "2.0",
			"method": "textDocument/didOpen",
			"params": [
				"textDocument": [
					"uri": uri.absoluteString,
					"languageId": languageID,
					"version": 1,
					"text": text,
				],
			],
		])
	}

	func completion(id: Int, uri: URL, in text: String, after prefix: String) throws {
		try send([
			"jsonrpc": "2.0",
			"id": id,
			"method": "textDocument/completion",
			"params": [
				"textDocument": ["uri": uri.absoluteString],
				"position": text.position(after: prefix),
			],
		])
	}

	func send(_ message: [String: Any]) throws {
		let body = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
		try sendBody(body)
	}

	func sendBody(_ body: Data) throws {
		let header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
		input.fileHandleForWriting.write(header + body)
	}

	private mutating func readAvailableOutput() {
		let fileDescriptor = output.fileHandleForReading.fileDescriptor
		var bytes = [UInt8](repeating: 0, count: 4096)
		while true {
			let byteCount = bytes.withUnsafeMutableBytes { buffer in
				#if canImport(Darwin)
				Darwin.read(fileDescriptor, buffer.baseAddress, buffer.count)
				#elseif canImport(Glibc)
				Glibc.read(fileDescriptor, buffer.baseAddress, buffer.count)
				#endif
			}
			guard byteCount > 0 else {
				return
			}
			outputBuffer.append(contentsOf: bytes.prefix(Int(byteCount)))
		}
	}

	private func restoreBlockingReads() {
		_ = fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL, outputFileDescriptorFlags)
	}

	private static func enableNonblockingReads(for fileHandle: FileHandle) -> Int32? {
		let flags = fcntl(fileHandle.fileDescriptor, F_GETFL)
		guard flags >= 0 else {
			return nil
		}
		_ = fcntl(fileHandle.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
		return flags
	}

	private static func messages(in data: Data) throws -> [[String: Any]] {
		var buffer = data
		var messages: [[String: Any]] = []
		while let body = body(in: &buffer) {
			let json = try JSONSerialization.jsonObject(with: body)
			messages.append(try #require(json as? [String: Any]))
		}
		return messages
	}

	private static func body(in buffer: inout Data) -> Data? {
		guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
			return nil
		}
		let header = String(decoding: buffer[..<headerRange.lowerBound], as: UTF8.self)
		guard
			let length = header
				.components(separatedBy: "\r\n")
				.first(where: { $0.lowercased().hasPrefix("content-length:") })?
				.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
				.last
				.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) })
		else {
			return nil
		}
		let bodyStart = headerRange.upperBound
		let bodyEnd = bodyStart + length
		guard buffer.count >= bodyEnd else {
			return nil
		}
		let body = Data(buffer[bodyStart..<bodyEnd])
		buffer.removeSubrange(..<bodyEnd)
		return body
	}

	private static func packageRoot() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		for _ in 0..<3 {
			url.deleteLastPathComponent()
		}
		return url
	}

}

private final class TemporaryDirectory {
	let url: URL

	init() throws {
		url = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconLSPCommandTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}

	func write(_ relativePath: String, _ text: String) throws {
		let url = url.appendingPathComponent(relativePath)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try Data(text.utf8).write(to: url)
	}

	deinit {
		try? FileManager.default.removeItem(at: url)
	}
}

private extension Dictionary where Key == String, Value == Any {
	var integerID: Int? {
		id as? Int
	}

	var id: Any? {
		self["id"]
	}

	var errorCode: Int? {
		(error?["code"] as? Int)
	}

	var error: [String: Any]? {
		self["error"] as? [String: Any]
	}

	var completionLabels: [String] {
		guard
			let result = self["result"] as? [String: Any],
			let items = result["items"] as? [[String: Any]]
		else {
			return []
		}
		return items.compactMap { $0["label"] as? String }
	}
}

private extension Array where Element == [String: Any] {
	func response(id: Int) -> [String: Any]? {
		first { $0.integerID == id }
	}

	func diagnostics(uri: URL) -> [String] {
		flatMap { message -> [String] in
			guard
				message["method"] as? String == "textDocument/publishDiagnostics",
				let params = message["params"] as? [String: Any],
				params["uri"] as? String == uri.absoluteString,
				let diagnostics = params["diagnostics"] as? [[String: Any]]
			else {
				return []
			}
			return diagnostics.compactMap { $0["message"] as? String }
		}
	}
}

private extension String {
	func position(after prefix: String) -> [String: Int] {
		let character = hasPrefix(prefix) ? prefix.utf16.count : utf16.count
		return ["line": 0, "character": character]
	}
}
