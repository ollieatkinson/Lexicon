//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

final class LexiconLanguageServer {
	private var workspace: LexiconWorkspace
	private var workspaceRoots: [URL] = []
	private var documents: [String: String] = [:]
	private let transport: LSPTransport
	private let decoder = JSONDecoder()

	init(
		workspace: LexiconWorkspace,
		transport: LSPTransport = LSPTransport()
	) {
		self.workspace = workspace
		self.transport = transport
	}

	func run() {
		while let body = transport.readMessage() {
			guard let request = try? decoder.decode(LSPRequest.self, from: body) else {
				continue
			}
			switch request.method {
			case LSPMethod.initialize:
				initialize(body, id: request.id)
			case LSPMethod.shutdown:
				respond(request.id, result: LSPNull())
			case LSPMethod.exit:
				return
			case LSPMethod.didOpen:
				didOpen(body)
			case LSPMethod.didChange:
				didChange(body)
			case LSPMethod.completion:
				complete(body, id: request.id)
			default:
				respond(request.id, result: LSPNull())
			}
		}
	}

	private func initialize(_ body: Data, id: LSPRequestID?) {
		let params = decodeParams(InitializeParams.self, from: body) ?? InitializeParams()
		configureWorkspace(params)
		respond(id, result: InitializeResult())
	}

	private func configureWorkspace(_ params: InitializeParams) {
		var roots = params.workspaceFolders?.compactMap { $0.uri.fileURL } ?? []
		if let root = params.rootUri?.fileURL {
			roots.append(root)
		}
		workspaceRoots = roots.uniquedByPath()
		workspace.reloadConfiguration(workspaceRoots: workspaceRoots)
	}

	private func didOpen(_ body: Data) {
		guard let params = decodeParams(DidOpenTextDocumentParams.self, from: body) else {
			return
		}
		let uri = params.textDocument.uri
		let text = params.textDocument.text
		documents[uri] = text
		refreshIndexIfNeeded(uri: uri, text: text)
		publishDiagnostics(uri: uri, text: text)
	}

	private func didChange(_ body: Data) {
		guard
			let params = decodeParams(DidChangeTextDocumentParams.self, from: body),
			let text = params.contentChanges.first?.text
		else {
			return
		}
		let uri = params.textDocument.uri
		documents[uri] = text
		refreshIndexIfNeeded(uri: uri, text: text)
		publishDiagnostics(uri: uri, text: text)
	}

	private func refreshIndexIfNeeded(uri: String, text: String) {
		if isConfigurationDocument(uri: uri) {
			workspace.reloadConfiguration(workspaceRoots: workspaceRoots)
			return
		}
		guard isLexiconDocument(uri: uri) else {
			return
		}
		workspace.refreshLexicon(uri: uri, text: text)
	}

	private func isLexiconDocument(uri: String) -> Bool {
		workspace.isLexiconDocument(uri: uri) || uri.fileURL?.pathExtension == "lexicon"
	}

	private func isConfigurationDocument(uri: String) -> Bool {
		guard let url = uri.fileURL else {
			return false
		}
		return LexiconWorkspace.configurationFileNames.contains(url.lastPathComponent)
	}

	private func complete(_ body: Data, id: LSPRequestID?) {
		guard
			let params = decodeParams(CompletionParams.self, from: body),
			let text = documents[params.textDocument.uri] ?? fileText(uri: params.textDocument.uri)
		else {
			respond(id, result: CompletionList.empty)
			return
		}
		let uri = params.textDocument.uri
		refreshIndexIfNeeded(uri: uri, text: text)
		let service = LexiconLSPService(index: workspace.index(for: uri))
		guard let result = service.completion(
			in: text,
			line: params.position.line,
			character: params.position.character
		) else {
			respond(id, result: CompletionList.empty)
			return
		}
		respond(id, result: CompletionList(result))
	}

	private func fileText(uri: String) -> String? {
		guard let url = uri.fileURL else {
			return nil
		}
		return try? String(contentsOf: url, encoding: .utf8)
	}

	private func publishDiagnostics(uri: String, text: String) {
		let diagnostics = LexiconLSPService(index: workspace.index(for: uri))
			.diagnostics(in: text, lexiconDocument: isLexiconDocument(uri: uri))
			.map(Diagnostic.init)
		transport.notify(
			method: LSPMethod.publishDiagnostics,
			params: PublishDiagnosticsParams(uri: uri, diagnostics: diagnostics)
		)
	}

	private func respond<Result: Encodable>(_ id: LSPRequestID?, result: Result) {
		guard let id else {
			return
		}
		transport.respond(id: id, result: result)
	}

	private func decodeParams<Params: Decodable>(_ type: Params.Type, from body: Data) -> Params? {
		try? decoder.decode(LSPMessage<Params>.self, from: body).params
	}
}
