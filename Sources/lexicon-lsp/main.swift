//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

@main
struct LexiconLSPCommand {

	static func main() {
		let server = LexiconLanguageServer(configuration: loadConfiguration())
		server.run()
	}

	static func loadConfiguration() -> LexiconLanguageServerConfiguration {
		let arguments = CommandLine.arguments.dropFirst()
		guard
			let option = arguments.firstIndex(of: "--lexicon"),
			arguments.indices.contains(arguments.index(after: option))
		else {
			return LexiconLanguageServerConfiguration()
		}
		let path = arguments[arguments.index(after: option)]
		let url = URL(fileURLWithPath: path).standardizedFileURL
		return LexiconLanguageServerConfiguration(explicitLexiconURL: url)
	}
}

final class LexiconLanguageServer {
	private var configuration: LexiconLanguageServerConfiguration
	private var workspaceRoots: [URL] = []
	private var documents: [String: String] = [:]
	private let input = FileHandle.standardInput
	private let output = FileHandle.standardOutput
	private var buffer = Data()

	init(configuration: LexiconLanguageServerConfiguration) {
		self.configuration = configuration
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
				configureWorkspace(object)
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

	private func configureWorkspace(_ object: [String: Any]) {
		guard let params = object["params"] as? [String: Any] else {
			return
		}
		var roots: [URL] = []
		if let workspaceFolders = params["workspaceFolders"] as? [[String: Any]] {
			roots.append(contentsOf: workspaceFolders.compactMap { folder in
				(folder["uri"] as? String).flatMap(fileURL)
			})
		}
		if let rootURI = params["rootUri"] as? String, let url = fileURL(rootURI) {
			roots.append(url)
		}
		workspaceRoots = roots.uniquedByPath()
		configuration.reloadWorkspaceConfiguration(workspaceRoots: workspaceRoots)
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
		if isConfigurationDocument(uri: uri) {
			configuration.reloadWorkspaceConfiguration(workspaceRoots: workspaceRoots)
			return
		}
		guard isLexiconDocument(uri: uri) else {
			return
		}
		configuration.refreshLexicon(uri: uri, text: text)
	}

	private func isLexiconDocument(uri: String) -> Bool {
		configuration.isLexiconDocument(uri: uri) || URL(string: uri)?.pathExtension == "lexicon"
	}

	private func isConfigurationDocument(uri: String) -> Bool {
		guard let url = URL(string: uri), url.isFileURL else {
			return false
		}
		return LexiconLanguageServerConfiguration.configurationFileNames.contains(url.lastPathComponent)
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
		let index = configuration.index(for: uri)
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
		let diagnostics = LexiconLSPService(index: configuration.index(for: uri)).diagnostics(in: text)
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

	private func fileURL(_ uri: String) -> URL? {
		guard let url = URL(string: uri), url.isFileURL else {
			return nil
		}
		return url.standardizedFileURL
	}
}

struct LexiconLanguageServerConfiguration {
	static let configurationFileNames = [
		"lexicon-lsp.json",
		".lexicon-lsp.json",
		"lexicon.conf",
	]

	private var explicitLexiconURL: URL?
	private var fallbackIndex = LexiconPathIndex()
	private var mappings: [LexiconIndexMapping] = []

	init(explicitLexiconURL: URL? = nil) {
		self.explicitLexiconURL = explicitLexiconURL
		if let explicitLexiconURL {
			fallbackIndex = (try? LexiconPathIndex(lexiconURL: explicitLexiconURL)) ?? LexiconPathIndex()
		}
	}

	func index(for uri: String) -> LexiconPathIndex {
		guard let url = fileURL(uri) else {
			return fallbackIndex
		}
		return mappings
			.filter { $0.contains(url) }
			.sorted { $0.scopeURL.path.count > $1.scopeURL.path.count }
			.first?
			.index ?? fallbackIndex
	}

	func isLexiconDocument(uri: String) -> Bool {
		guard let url = fileURL(uri) else {
			return false
		}
		return explicitLexiconURL == url || mappings.contains { $0.lexiconURL == url }
	}

	mutating func refreshLexicon(uri: String, text: String) {
		guard let url = fileURL(uri) else {
			return
		}
		let index = try? LexiconPathIndex(
			lexiconText: text,
			baseURL: url.deletingLastPathComponent()
		)
		for offset in mappings.indices where mappings[offset].lexiconURL == url {
			mappings[offset].index = index ?? mappings[offset].index
		}
		if explicitLexiconURL == url || url.pathExtension == "lexicon" {
			fallbackIndex = index ?? fallbackIndex
			explicitLexiconURL = explicitLexiconURL ?? url
		}
	}

	mutating func reloadWorkspaceConfiguration(workspaceRoots: [URL]) {
		mappings = workspaceRoots.flatMap(Self.loadMappings)
		if let explicitLexiconURL {
			fallbackIndex = (try? LexiconPathIndex(lexiconURL: explicitLexiconURL)) ?? fallbackIndex
		}
	}

	private static func loadMappings(workspaceRoot: URL) -> [LexiconIndexMapping] {
		configurationFileNames.flatMap { name -> [LexiconIndexMapping] in
			let url = workspaceRoot.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: url.path) else {
				return []
			}
			return (try? ProjectConfiguration(url: url).mappings()) ?? []
		}
	}

	private func fileURL(_ uri: String) -> URL? {
		guard let url = URL(string: uri), url.isFileURL else {
			return nil
		}
		return url.standardizedFileURL
	}
}

private struct ProjectConfiguration {
	var lexicon: String?
	var scope: String?
	var lexicons: [Entry]?
	var configurationURL: URL

	struct Entry: Decodable {
		var scope: String?
		var lexicon: String
	}

	init(url: URL) throws {
		let data = try Data(contentsOf: url)
		let decoded = try JSONDecoder().decode(ProjectConfigurationFile.self, from: data)
		self.lexicon = decoded.lexicon
		self.scope = decoded.scope
		self.lexicons = decoded.lexicons
		self.configurationURL = url
	}

	func mappings() throws -> [LexiconIndexMapping] {
		let directory = configurationURL.deletingLastPathComponent()
		let entries = lexicons ?? lexicon.map { [Entry(scope: scope, lexicon: $0)] } ?? []
		return entries.compactMap { entry in
			let lexiconURL = URL(fileURLWithPath: entry.lexicon, relativeTo: directory)
				.standardizedFileURL
			let scopeURL = URL(fileURLWithPath: entry.scope ?? ".", relativeTo: directory)
				.standardizedFileURL
			guard let index = try? LexiconPathIndex(lexiconURL: lexiconURL) else {
				return nil
			}
			return LexiconIndexMapping(
				scopeURL: scopeURL,
				lexiconURL: lexiconURL,
				index: index
			)
		}
	}
}

private struct ProjectConfigurationFile: Decodable {
	var lexicon: String?
	var scope: String?
	var lexicons: [ProjectConfiguration.Entry]?
}

private struct LexiconIndexMapping {
	var scopeURL: URL
	var lexiconURL: URL
	var index: LexiconPathIndex

	func contains(_ url: URL) -> Bool {
		let scope = scopeURL.standardizedFileURL.resolvingSymlinksInPath().path
		let path = url.standardizedFileURL.resolvingSymlinksInPath().path
		return path == scope || path.hasPrefix(scope + "/")
	}
}

private extension Array where Element == URL {
	func uniquedByPath() -> [URL] {
		var seen: Set<String> = []
		return filter { url in
			seen.insert(url.standardizedFileURL.path).inserted
		}
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
