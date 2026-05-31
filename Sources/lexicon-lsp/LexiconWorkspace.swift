//
// github.com/screensailor 2026
//

import Foundation
import Lexicon
import LexiconLSP

struct LexiconWorkspace {
	static let configurationFileNames = [
		"lexicon-lsp.json",
		".lexicon-lsp.json",
		"lexicon.conf",
		".lexicon.conf",
	]

	private var explicitLexiconURL: URL?
	private var fallback = LexiconWorkspaceIndex()
	private var mappings: [LexiconIndexMapping] = []
	private var configurationDiagnostics: [URL: [LexiconDiagnostic]] = [:]
	private var openDocuments: [URL: String] = [:]

	init(explicitLexiconURL: URL? = nil) {
		self.explicitLexiconURL = explicitLexiconURL?.lspCanonicalFileURL
		rebuildFallbackIndex()
	}

	func index(for uri: String) -> LexiconPathIndex {
		indexMapping(for: uri)?.index ?? fallback.index
	}

	func diagnostics(for uri: String) -> [LexiconDiagnostic] {
		guard let url = uri.fileURL else {
			return []
		}
		if Self.isConfigurationURL(url) {
			return configurationDiagnostics[url.lspCanonicalFileURL] ?? []
		}
		return indexMapping(for: uri)?.diagnostics ?? fallback.diagnostics
	}

	func isLexiconDocument(uri: String) -> Bool {
		guard let url = uri.fileURL?.lspCanonicalFileURL else {
			return false
		}
		return explicitLexiconURL == url || mappings.contains { $0.lexiconURL == url }
	}

	@discardableResult
	mutating func updateDocument(uri: String, text: String, workspaceRoots: [URL]) -> Bool {
		guard let url = uri.fileURL?.lspCanonicalFileURL else {
			return false
		}
		let isConfiguration = Self.isConfigurationURL(url)
		let isLexicon = url.pathExtension == "lexicon"
		guard isConfiguration || isLexicon else {
			return false
		}
		openDocuments[url] = text
		if isConfiguration {
			reloadConfiguration(workspaceRoots: workspaceRoots)
		} else {
			adoptFallbackLexiconIfNeeded(url)
			rebuildIndexes()
		}
		return true
	}

	mutating func reloadConfiguration(workspaceRoots: [URL]) {
		let result = Self.loadMappings(
			workspaceRoots: workspaceRoots.map(\.lspCanonicalFileURL),
			openDocuments: openDocuments
		)
		mappings = result.mappings
		configurationDiagnostics = result.configurationDiagnostics
		rebuildFallbackIndex()
	}

	private func indexMapping(for uri: String) -> LexiconIndexMapping? {
		guard let url = uri.fileURL else {
			return nil
		}
		return mappings
			.filter { $0.contains(url) }
			.sorted { $0.scopeURL.path.count > $1.scopeURL.path.count }
			.first
	}

	private mutating func rebuildIndexes() {
		mappings = mappings.map { $0.rebuilt(openDocuments: openDocuments) }
		rebuildFallbackIndex()
	}

	private mutating func rebuildFallbackIndex() {
		if let explicitLexiconURL {
			fallback = LexiconWorkspaceIndex(lexiconURL: explicitLexiconURL, openDocuments: openDocuments)
		}
	}

	private mutating func adoptFallbackLexiconIfNeeded(_ url: URL) {
		guard explicitLexiconURL == nil, mappings.isEmpty, fallback.lexiconURL == nil else {
			return
		}
		explicitLexiconURL = url
	}

	private static func loadMappings(
		workspaceRoots: [URL],
		openDocuments: [URL: String]
	) -> LexiconConfigurationLoadResult {
		var mappings: [LexiconIndexMapping] = []
		var diagnostics: [URL: [LexiconDiagnostic]] = [:]
		for configurationURL in configurationURLs(workspaceRoots: workspaceRoots, openDocuments: openDocuments) {
			let result = LexiconProjectConfiguration.load(url: configurationURL, openDocuments: openDocuments)
			mappings.append(contentsOf: result.mappings)
			diagnostics[configurationURL, default: []].append(contentsOf: result.diagnostics)
		}
		return LexiconConfigurationLoadResult(
			mappings: mappings,
			configurationDiagnostics: diagnostics
		)
	}

	private static func configurationURLs(workspaceRoots: [URL], openDocuments: [URL: String]) -> [URL] {
		var urls: Set<URL> = []
		for root in workspaceRoots {
			urls.formUnion(discoverConfigurationURLs(in: root))
			for url in openDocuments.keys where isConfigurationURL(url) && url.isContained(in: root) {
				urls.insert(url)
			}
		}
		return urls.sorted { $0.path < $1.path }
	}

	private static func discoverConfigurationURLs(in root: URL) -> Set<URL> {
		var urls: Set<URL> = []
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsPackageDescendants]
		) else {
			return urls
		}
		for case let url as URL in enumerator {
			let name = url.lastPathComponent
			if skippedDirectoryNames.contains(name), (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
				enumerator.skipDescendants()
				continue
			}
			if isConfigurationURL(url) {
				urls.insert(url.lspCanonicalFileURL)
			}
		}
		return urls
	}

	private static let skippedDirectoryNames: Set<String> = [
		".build",
		".git",
		".swiftpm",
		"DerivedData",
		"node_modules",
		"target",
	]

	private static func isConfigurationURL(_ url: URL) -> Bool {
		configurationFileNames.contains(url.lastPathComponent)
	}
}

private struct LexiconConfigurationLoadResult {
	var mappings: [LexiconIndexMapping] = []
	var configurationDiagnostics: [URL: [LexiconDiagnostic]] = [:]
}

private struct LexiconProjectConfiguration {
	var configurationURL: URL
	var lexicon: String?
	var scope: String?
	var lexicons: [Entry]?

	struct Entry: Decodable {
		var scope: String?
		var lexicon: String
	}

	static func load(url: URL, openDocuments: [URL: String]) -> LexiconProjectConfigurationLoadResult {
		do {
			let configuration = try Self(url: url, openDocuments: openDocuments)
			return configuration.mappings(openDocuments: openDocuments)
		} catch {
			return LexiconProjectConfigurationLoadResult(
				diagnostics: [
					.workspace("Could not read Lexicon LSP configuration: \(error)")
				]
			)
		}
	}

	init(url: URL, openDocuments: [URL: String]) throws {
		let data: Data
		if let text = openDocuments[url.lspCanonicalFileURL] {
			data = Data(text.utf8)
		} else {
			data = try Data(contentsOf: url)
		}
		let decoded = try JSONDecoder().decode(LexiconProjectConfigurationFile.self, from: data)
		self.configurationURL = url.lspCanonicalFileURL
		self.lexicon = decoded.lexicon
		self.scope = decoded.scope
		self.lexicons = decoded.lexicons
	}

	func mappings(openDocuments: [URL: String]) -> LexiconProjectConfigurationLoadResult {
		let directory = configurationURL.deletingLastPathComponent()
		let entries = lexicons ?? lexicon.map { [Entry(scope: scope, lexicon: $0)] } ?? []
		guard entries.isEmpty == false else {
			return LexiconProjectConfigurationLoadResult(
				diagnostics: [
					.workspace("Lexicon LSP configuration must declare 'lexicon' or 'lexicons'.")
				]
			)
		}
		var mappings: [LexiconIndexMapping] = []
		var diagnostics: [LexiconDiagnostic] = []
		for entry in entries {
			let lexiconURL = URL(fileURLWithPath: entry.lexicon, relativeTo: directory).lspCanonicalFileURL
			let scopeURL = URL(fileURLWithPath: entry.scope ?? ".", relativeTo: directory).lspCanonicalFileURL
			let index = LexiconWorkspaceIndex(lexiconURL: lexiconURL, openDocuments: openDocuments)
			diagnostics.append(contentsOf: index.diagnostics)
			mappings.append(LexiconIndexMapping(
				scopeURL: scopeURL,
				lexiconURL: lexiconURL,
				index: index.index,
				diagnostics: index.diagnostics
			))
		}
		return LexiconProjectConfigurationLoadResult(mappings: mappings, diagnostics: diagnostics)
	}
}

private struct LexiconProjectConfigurationLoadResult {
	var mappings: [LexiconIndexMapping] = []
	var diagnostics: [LexiconDiagnostic] = []
}

private struct LexiconProjectConfigurationFile: Decodable {
	var lexicon: String?
	var scope: String?
	var lexicons: [LexiconProjectConfiguration.Entry]?
}

private struct LexiconWorkspaceIndex {
	var lexiconURL: URL?
	var index = LexiconPathIndex()
	var diagnostics: [LexiconDiagnostic] = []

	init() {}

	init(lexiconURL: URL, openDocuments: [URL: String]) {
		self.lexiconURL = lexiconURL
		do {
			let resolver = OpenDocumentLexiconImportResolver(
				baseURL: lexiconURL.deletingLastPathComponent(),
				openDocuments: openDocuments
			)
			let text = try Self.lexiconText(at: lexiconURL, openDocuments: openDocuments)
			index = try LexiconPathIndex(lexiconText: text, resolver: resolver)
		} catch {
			diagnostics = [
				.workspace("Could not load Lexicon index '\(lexiconURL.path)': \(error)")
			]
		}
	}

	private static func lexiconText(at url: URL, openDocuments: [URL: String]) throws -> String {
		if let text = openDocuments[url.lspCanonicalFileURL] {
			return text
		}
		return try String(contentsOf: url, encoding: .utf8)
	}
}

private struct LexiconIndexMapping {
	var scopeURL: URL
	var lexiconURL: URL
	var index: LexiconPathIndex
	var diagnostics: [LexiconDiagnostic]

	func rebuilt(openDocuments: [URL: String]) -> Self {
		let index = LexiconWorkspaceIndex(lexiconURL: lexiconURL, openDocuments: openDocuments)
		return Self(
			scopeURL: scopeURL,
			lexiconURL: lexiconURL,
			index: index.index,
			diagnostics: index.diagnostics
		)
	}

	func contains(_ url: URL) -> Bool {
		let scope = scopeURL.lspCanonicalFileURL.path
		let path = url.lspCanonicalFileURL.path
		return path == scope || path.hasPrefix(scope + "/")
	}
}

private struct OpenDocumentLexiconImportResolver: LexiconImportResolving {
	var baseURL: URL
	var openDocuments: [URL: String]
	var allowRemote = true

	func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		if `import`.location == .local, let url = localURL(for: `import`.reference), let text = openDocuments[url.lspCanonicalFileURL] {
			return try TaskPaper(text).decodeDocument()
		}
		return try FileLexiconImportResolver(
			baseURL: baseURL,
			allowRemote: allowRemote
		).resolve(`import`)
	}

	private func localURL(for reference: String) -> URL? {
		let base = baseURL.lspCanonicalFileURL
		let candidate = URL(fileURLWithPath: reference, relativeTo: base).lspCanonicalFileURL
		guard candidate.isFileURL else {
			return nil
		}
		guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else {
			return nil
		}
		return candidate
	}
}

private extension LexiconDiagnostic {
	static func workspace(_ message: String) -> Self {
		Self(
			range: LexiconTextRange(
				start: LexiconPosition(line: 0, character: 0),
				end: LexiconPosition(line: 0, character: 0)
			),
			message: message
		)
	}
}

extension String {
	var fileURL: URL? {
		guard let url = URL(string: self), url.isFileURL else {
			return nil
		}
		return url.lspCanonicalFileURL
	}
}

extension URL {
	var lspCanonicalFileURL: URL {
		standardizedFileURL.resolvingSymlinksInPath()
	}

	func isContained(in root: URL) -> Bool {
		let rootPath = root.lspCanonicalFileURL.path
		let path = lspCanonicalFileURL.path
		return path == rootPath || path.hasPrefix(rootPath + "/")
	}
}

extension Array where Element == URL {
	func uniquedByPath() -> [URL] {
		var seen: Set<String> = []
		return filter { url in
			seen.insert(url.lspCanonicalFileURL.path).inserted
		}
	}
}
