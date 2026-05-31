//
// github.com/screensailor 2026
//

import Foundation
import LexiconLSP

struct LexiconWorkspace {
	static let configurationFileNames = [
		"lexicon-lsp.json",
		".lexicon-lsp.json",
		"lexicon.conf",
		".lexicon.conf",
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
		guard let url = uri.fileURL else {
			return fallbackIndex
		}
		return mappings
			.filter { $0.contains(url) }
			.sorted { $0.scopeURL.path.count > $1.scopeURL.path.count }
			.first?
			.index ?? fallbackIndex
	}

	func isLexiconDocument(uri: String) -> Bool {
		guard let url = uri.fileURL else {
			return false
		}
		return explicitLexiconURL == url || mappings.contains { $0.lexiconURL == url }
	}

	mutating func refreshLexicon(uri: String, text: String) {
		guard let url = uri.fileURL else {
			return
		}
		let index = try? LexiconPathIndex(
			lexiconText: text,
			baseURL: url.deletingLastPathComponent()
		)
		for offset in mappings.indices where mappings[offset].lexiconURL == url {
			mappings[offset].index = index ?? mappings[offset].index
		}
		if mappings.isEmpty, explicitLexiconURL == nil, url.pathExtension == "lexicon" {
			fallbackIndex = index ?? fallbackIndex
			explicitLexiconURL = url
		} else if explicitLexiconURL == url {
			fallbackIndex = index ?? fallbackIndex
		}
	}

	mutating func reloadConfiguration(workspaceRoots: [URL]) {
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
			return (try? LexiconProjectConfiguration(url: url).mappings()) ?? []
		}
	}
}

private struct LexiconProjectConfiguration {
	var lexicon: String?
	var scope: String?
	var lexicons: [Entry]?
	var configurationURL: URL

	struct Entry: Decodable {
		var scope: String?
		var lexicon: String
	}

	init(url: URL) throws {
		let decoded = try JSONDecoder().decode(
			LexiconProjectConfigurationFile.self,
			from: Data(contentsOf: url)
		)
		self.lexicon = decoded.lexicon
		self.scope = decoded.scope
		self.lexicons = decoded.lexicons
		self.configurationURL = url
	}

	func mappings() -> [LexiconIndexMapping] {
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

private struct LexiconProjectConfigurationFile: Decodable {
	var lexicon: String?
	var scope: String?
	var lexicons: [LexiconProjectConfiguration.Entry]?
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

extension String {
	var fileURL: URL? {
		guard let url = URL(string: self), url.isFileURL else {
			return nil
		}
		return url.standardizedFileURL
	}
}

extension Array where Element == URL {
	func uniquedByPath() -> [URL] {
		var seen: Set<String> = []
		return filter { url in
			seen.insert(url.standardizedFileURL.path).inserted
		}
	}
}
