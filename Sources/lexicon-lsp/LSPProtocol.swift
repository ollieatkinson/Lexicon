//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

enum LSPMethod {
	static let initialize = "initialize"
	static let shutdown = "shutdown"
	static let exit = "exit"
	static let didOpen = "textDocument/didOpen"
	static let didChange = "textDocument/didChange"
	static let completion = "textDocument/completion"
	static let publishDiagnostics = "textDocument/publishDiagnostics"
}

enum LSPRequestID: Codable, Hashable {
	case integer(Int)
	case string(String)

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let value = try? container.decode(Int.self) {
			self = .integer(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else {
			throw DecodingError.typeMismatch(
				Self.self,
				.init(codingPath: decoder.codingPath, debugDescription: "Expected string or integer request id.")
			)
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .integer(let value):
			try container.encode(value)
		case .string(let value):
			try container.encode(value)
		}
	}
}

struct LSPRequest: Decodable {
	var id: LSPRequestID?
	var method: String
}

struct LSPMessage<Params: Decodable>: Decodable {
	var params: Params?
}

struct LSPResponse<Result: Encodable>: Encodable {
	var jsonrpc = "2.0"
	var id: LSPRequestID
	var result: Result
}

struct LSPNotification<Params: Encodable>: Encodable {
	var jsonrpc = "2.0"
	var method: String
	var params: Params
}

struct LSPNull: Encodable {
	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encodeNil()
	}
}

struct InitializeParams: Decodable {
	var rootUri: String?
	var workspaceFolders: [WorkspaceFolder]?

	init(rootUri: String? = nil, workspaceFolders: [WorkspaceFolder]? = nil) {
		self.rootUri = rootUri
		self.workspaceFolders = workspaceFolders
	}
}

struct WorkspaceFolder: Decodable {
	var uri: String
	var name: String?
}

struct InitializeResult: Encodable {
	var capabilities = ServerCapabilities()
}

struct ServerCapabilities: Encodable {
	var textDocumentSync = 1
	var completionProvider = CompletionProvider()
}

struct CompletionProvider: Encodable {
	var triggerCharacters = [".", "\"", "("]
}

struct TextDocumentIdentifier: Codable {
	var uri: String
}

struct TextDocumentItem: Decodable {
	var uri: String
	var languageId: String?
	var version: Int?
	var text: String
}

struct VersionedTextDocumentIdentifier: Decodable {
	var uri: String
	var version: Int?
}

struct DidOpenTextDocumentParams: Decodable {
	var textDocument: TextDocumentItem
}

struct DidChangeTextDocumentParams: Decodable {
	var textDocument: VersionedTextDocumentIdentifier
	var contentChanges: [TextDocumentContentChangeEvent]
}

struct TextDocumentContentChangeEvent: Decodable {
	var text: String
}

struct CompletionParams: Decodable {
	var textDocument: TextDocumentIdentifier
	var position: LexiconPosition
}

struct CompletionList: Encodable {
	var isIncomplete = false
	var items: [CompletionItem]

	static let empty = CompletionList(items: [])

	init(items: [CompletionItem] = []) {
		self.items = items
	}

	init(_ result: LexiconCompletionResult) {
		self.items = result.items.map { CompletionItem($0, range: result.range) }
	}
}

struct CompletionItem: Encodable {
	var label: String
	var insertText: String
	var kind = 10
	var textEdit: TextEdit

	init(_ completion: LexiconCompletion, range: LexiconTextRange) {
		self.label = completion.label
		self.insertText = completion.insertText
		self.textEdit = TextEdit(range: range, newText: completion.insertText)
	}
}

struct TextEdit: Encodable {
	var range: LexiconTextRange
	var newText: String
}

struct PublishDiagnosticsParams: Encodable {
	var uri: String
	var diagnostics: [Diagnostic]
}

struct Diagnostic: Encodable {
	var range: LexiconTextRange
	var severity = 1
	var source = "lexicon"
	var message: String

	init(_ diagnostic: LexiconDiagnostic) {
		self.range = diagnostic.range
		self.message = diagnostic.message
	}
}
