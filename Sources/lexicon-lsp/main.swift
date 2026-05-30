//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

@main
struct LexiconLSPCommand {

	static func main() {
		let configuration = loadConfiguration()
		let server = LexiconLanguageServer(
			index: configuration.index,
			lexiconURI: configuration.lexiconURI
		)
		server.run()
	}

	static func loadConfiguration() -> (index: LexiconPathIndex, lexiconURI: String?) {
		let arguments = CommandLine.arguments.dropFirst()
		guard
			let option = arguments.firstIndex(of: "--lexicon"),
			arguments.indices.contains(arguments.index(after: option))
		else {
			return (LexiconPathIndex(), nil)
		}
		let path = arguments[arguments.index(after: option)]
		let url = URL(fileURLWithPath: path).standardizedFileURL
		do {
			let text = try String(contentsOf: url, encoding: .utf8)
			return (try LexiconPathIndex(lexiconText: text), url.absoluteString)
		} catch {
			return (LexiconPathIndex(), url.absoluteString)
		}
	}
}

final class LexiconLanguageServer {
	private var index: LexiconPathIndex
	private let lexiconURI: String?
	private var documents: [String: String] = [:]
	private let input = FileHandle.standardInput
	private let output = FileHandle.standardOutput
	private var buffer = Data()

	init(index: LexiconPathIndex, lexiconURI: String?) {
		self.index = index
		self.lexiconURI = lexiconURI
	}

	func run() {
		while let body = readMessage() {
			guard
				let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
				let method = object["method"] as? String
			else {
				continue
			}
			let id = object["id"]
			switch method {
			case "initialize":
				respond(id: id, result: initializeResult)
			case "shutdown":
				respond(id: id, result: NSNull())
			case "exit":
				return
			case "textDocument/didOpen":
				didOpen(object)
			case "textDocument/didChange":
				didChange(object)
			case "textDocument/completion":
				complete(object, id: id)
			default:
				if id != nil {
					respond(id: id, result: NSNull())
				}
			}
		}
	}

	private var initializeResult: [String: Any] {
		[
			"capabilities": [
				"textDocumentSync": 1,
				"completionProvider": [
					"triggerCharacters": [".", "\"", "("]
				]
			]
		]
	}

	private func didOpen(_ object: [String: Any]) {
		guard
			let params = object["params"] as? [String: Any],
			let textDocument = params["textDocument"] as? [String: Any],
			let uri = textDocument["uri"] as? String,
			let text = textDocument["text"] as? String
		else {
			return
		}
		documents[uri] = text
		refreshIndexIfNeeded(uri: uri, text: text)
		publishDiagnostics(uri: uri, text: text)
	}

	private func didChange(_ object: [String: Any]) {
		guard
			let params = object["params"] as? [String: Any],
			let textDocument = params["textDocument"] as? [String: Any],
			let uri = textDocument["uri"] as? String,
			let changes = params["contentChanges"] as? [[String: Any]],
			let text = changes.first?["text"] as? String
		else {
			return
		}
		documents[uri] = text
		refreshIndexIfNeeded(uri: uri, text: text)
		publishDiagnostics(uri: uri, text: text)
	}

	private func refreshIndexIfNeeded(uri: String, text: String) {
		guard isLexiconDocument(uri: uri) else {
			return
		}
		if let nextIndex = try? LexiconPathIndex(lexiconText: text) {
			index = nextIndex
		}
	}

	private func isLexiconDocument(uri: String) -> Bool {
		if uri == lexiconURI {
			return true
		}
		return URL(string: uri)?.pathExtension == "lexicon"
	}

	private func complete(_ object: [String: Any], id: Any?) {
		guard
			let params = object["params"] as? [String: Any],
			let textDocument = params["textDocument"] as? [String: Any],
			let uri = textDocument["uri"] as? String,
			let position = params["position"] as? [String: Any],
			let line = position["line"] as? Int,
			let character = position["character"] as? Int,
			let text = documents[uri] ?? fileText(uri: uri)
		else {
			respond(id: id, result: ["isIncomplete": false, "items": []])
			return
		}
		refreshIndexIfNeeded(uri: uri, text: text)
		guard let result = LexiconLSPService(index: index).completion(in: text, line: line, character: character) else {
			respond(id: id, result: ["isIncomplete": false, "items": []])
			return
		}
		respond(id: id, result: [
			"isIncomplete": false,
			"items": result.items.map { item in
				[
					"label": item.label,
					"insertText": item.insertText,
					"kind": 10,
					"textEdit": [
						"range": result.range.lspValue,
						"newText": item.insertText
					]
				]
			}
		])
	}

	private func fileText(uri: String) -> String? {
		guard
			let url = URL(string: uri),
			url.isFileURL
		else {
			return nil
		}
		return try? String(contentsOf: url, encoding: .utf8)
	}

	private func publishDiagnostics(uri: String, text: String) {
		let diagnostics = LexiconLSPService(index: index).diagnostics(in: text)
		notify(method: "textDocument/publishDiagnostics", params: [
			"uri": uri,
			"diagnostics": diagnostics.map { diagnostic in
				[
					"range": diagnostic.range.lspValue,
					"severity": 1,
					"source": "lexicon",
					"message": diagnostic.message
				]
			}
		])
	}

	private func respond(id: Any?, result: Any) {
		write([
			"jsonrpc": "2.0",
			"id": id ?? NSNull(),
			"result": result
		])
	}

	private func notify(method: String, params: Any) {
		write([
			"jsonrpc": "2.0",
			"method": method,
			"params": params
		])
	}

	private func write(_ object: [String: Any]) {
		guard let data = try? JSONSerialization.data(withJSONObject: object) else {
			return
		}
		let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
		output.write(header + data)
	}

	private func readMessage() -> Data? {
		while true {
			if let headerRange = headerRange(in: buffer) {
				let headerData = buffer[..<headerRange.lowerBound]
				let header = String(decoding: headerData, as: UTF8.self)
				let lengthParts = header
					.replacingOccurrences(of: "\r", with: "")
					.components(separatedBy: "\n")
					.first(where: { $0.lowercased().hasPrefix("content-length:") })?
					.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
				guard
					let lengthParts,
					lengthParts.count == 2,
					let length = Int(lengthParts[1].trimmingCharacters(in: .whitespaces))
				else {
					return nil
				}
				let bodyStart = headerRange.upperBound
				let bodyEnd = bodyStart + length
				if buffer.count >= bodyEnd {
					let body = buffer[bodyStart..<bodyEnd]
					buffer.removeSubrange(..<bodyEnd)
					return Data(body)
				}
			}
			guard let chunk = try? input.read(upToCount: 1), chunk.isEmpty == false else {
				return nil
			}
			buffer.append(chunk)
		}
	}

	private func headerRange(in data: Data) -> Range<Data.Index>? {
		data.range(of: Data("\r\n\r\n".utf8))
			?? data.range(of: Data("\n\n".utf8))
	}
}

private extension LexiconTextRange {
	var lspValue: [String: Any] {
		[
			"start": start.lspValue,
			"end": end.lspValue
		]
	}
}

private extension LexiconPosition {
	var lspValue: [String: Int] {
		[
			"line": line,
			"character": character
		]
	}
}
