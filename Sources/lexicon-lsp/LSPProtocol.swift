//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

struct LSPMethod: Codable, ExpressibleByStringLiteral, Hashable, RawRepresentable {
	var rawValue: String

	init(rawValue: String) {
		self.rawValue = rawValue
	}

	init(stringLiteral value: String) {
		rawValue = value
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		rawValue = try container.decode(String.self)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}

	static let initialize: Self = "initialize"
	static let shutdown: Self = "shutdown"
	static let exit: Self = "exit"
	static let didOpen: Self = "textDocument/didOpen"
	static let didChange: Self = "textDocument/didChange"
	static let completion: Self = "textDocument/completion"
	static let publishDiagnostics: Self = "textDocument/publishDiagnostics"
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
	var method: LSPMethod
}

struct LSPMessage<Params: Decodable>: Decodable {
	var params: Params?
}

struct LSPResponse<Result: Encodable>: Encodable {
	var jsonrpc = "2.0"
	var id: LSPRequestID
	var result: Result
}

struct LSPErrorResponse: Encodable {
	var jsonrpc = "2.0"
	var id: LSPRequestID?
	var error: LSPResponseError

	private enum CodingKeys: String, CodingKey {
		case jsonrpc
		case id
		case error
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(jsonrpc, forKey: .jsonrpc)
		if let id {
			try container.encode(id, forKey: .id)
		} else {
			try container.encodeNil(forKey: .id)
		}
		try container.encode(error, forKey: .error)
	}
}

struct LSPResponseError: Error, Encodable {
	var code: Int
	var message: String

	static func invalidRequest(_ message: String) -> Self {
		Self(code: -32600, message: message)
	}

	static func methodNotFound(_ message: String) -> Self {
		Self(code: -32601, message: message)
	}

	static func invalidParams(_ message: String) -> Self {
		Self(code: -32602, message: message)
	}
}

struct LSPNotification<Params: Encodable>: Encodable {
	var jsonrpc = "2.0"
	var method: LSPMethod
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
