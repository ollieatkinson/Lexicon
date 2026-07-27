//
// github.com/screensailor 2026
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol LexiconImportResolving: Sendable {
	/// Stable identity of the source document being composed, when known.
	///
	/// Resolvers should provide this for file-backed documents so an import
	/// cycle that returns to the source can be diagnosed without comparing
	/// document contents.
	var rootIdentity: String? { get }

	func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document?
}

public struct ResolvedLexiconImport: Sendable {
	public var document: Lexicon.Document
	public var origin: URL?
	public var identity: String

	public init(
		document: Lexicon.Document,
		origin: URL?,
		identity: String
	) {
		self.document = document
		self.origin = origin
		self.identity = identity
	}
}

public protocol ContextualLexiconImportResolving: LexiconImportResolving {
	/// Resolves an import relative to the document that declared it.
	func resolve(
		_ import: Lexicon.Import,
		relativeTo origin: URL?
	) throws -> ResolvedLexiconImport?
}

public extension LexiconImportResolving {
	var rootIdentity: String? { nil }
}

public struct EmptyLexiconImportResolver: LexiconImportResolving {
	public init() {}

	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		nil
	}
}

public struct DictionaryLexiconImportResolver: ContextualLexiconImportResolving {
	public var documents: [String: Lexicon.Document]
	public var rootIdentity: String?

	public init(
		_ documents: [String: Lexicon.Document],
		rootIdentity: String? = nil
	) {
		self.documents = documents
		self.rootIdentity = rootIdentity
	}

	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		documents[`import`.reference]
	}

	public func resolve(
		_ import: Lexicon.Import,
		relativeTo origin: URL?
	) throws -> ResolvedLexiconImport? {
		documents[`import`.reference].map {
			.init(
				document: $0,
				origin: nil,
				identity: `import`.reference
			)
		}
	}
}

public struct FileLexiconImportResolver: ContextualLexiconImportResolving {
	/// Maximum accepted body size for one remote import (1 MiB).
	///
	/// Remote responses are rejected from their declared content length when
	/// available, or while streaming as soon as this limit would be exceeded.
	public static let maximumRemoteResponseBytes = 1_048_576

	public var baseURL: URL
	public var allowRemote: Bool
	public var rootURL: URL?

	public init(
		baseURL: URL,
		allowRemote: Bool = false,
		rootURL: URL? = nil
	) {
		self.baseURL = baseURL
		self.allowRemote = allowRemote
		self.rootURL = rootURL
	}

	public var rootIdentity: String? {
		rootURL?.lexiconImportIdentity
	}

	public func resolve(_ import: Lexicon.Import) throws -> Lexicon.Document? {
		try resolved(`import`, relativeTo: nil)?.document
	}

	public func resolve(
		_ import: Lexicon.Import,
		relativeTo origin: URL?
	) throws -> ResolvedLexiconImport? {
		try resolved(`import`, relativeTo: origin)
	}
}

public extension Lexicon {

	struct MergeConflict: Hashable, Sendable, CustomStringConvertible {
		public enum Kind: String, Hashable, Sendable {
			case importResolution
			case invalidGraft
		}

		public var kind: Kind
		public var path: String
		public var existing: String
		public var incoming: String

		public init(
			kind: Kind,
			path: String,
			existing: String,
			incoming: String
		) {
			self.kind = kind
			self.path = path
			self.existing = existing
			self.incoming = incoming
		}

		public var description: String {
			"\(kind.rawValue) conflict at \(path): \(existing) <> \(incoming)"
		}
	}

	struct MergePlan: Sendable {
		public var document: Document
		public var conflicts: [MergeConflict]

		public init(document: Document, conflicts: [MergeConflict]) {
			self.document = document
			self.conflicts = conflicts
		}

		public var hasConflicts: Bool {
			conflicts.isNotEmpty
		}
	}
}

public extension Lexicon.Document {

	/// Overlays documents from first to last. Later documents win at every
	/// declared node field while ordered metadata is appended in source order.
	static func merge(_ documents: [Self]) -> Lexicon.MergePlan {
		var merged = Lexicon.Document()
		for document in documents {
			merged.overlay(document)
		}
		return .init(document: merged, conflicts: [])
	}

	func merging(_ other: Self) -> Lexicon.MergePlan {
		Self.merge([self, other])
	}

	func composed(
		resolving resolver: LexiconImportResolving = EmptyLexiconImportResolver()
	) throws -> Lexicon.MergePlan {
		try composed(
			resolving: resolver,
			origin: nil,
			visited: resolver.rootIdentity.map { [$0] } ?? []
		)
	}
}

private extension Lexicon.Document {

	func composed(
		resolving resolver: LexiconImportResolving,
		origin: URL?,
		visited: Set<String>
	) throws -> Lexicon.MergePlan {
		var overlays: [Lexicon.Document] = []
		var conflicts: [Lexicon.MergeConflict] = []
		var local = self

		for `import` in imports {
			let resolved: ResolvedLexiconImport?
			do {
				resolved = try resolve(`import`, using: resolver, relativeTo: origin)
			} catch {
				conflicts.append(.init(
					kind: .importResolution,
					path: `import`.reference,
					existing: "load failed",
					incoming: error.localizedDescription
				))
				continue
			}
			guard let resolved else {
				conflicts.append(.init(
					kind: .importResolution,
					path: `import`.reference,
					existing: "unresolved",
					incoming: `import`.location.rawValue
				))
				continue
			}
			guard !visited.contains(resolved.identity) else {
				conflicts.append(.init(
					kind: .importResolution,
					path: `import`.reference,
					existing: "import cycle",
					incoming: resolved.identity
				))
				continue
			}
			let imported = try resolved.document.composed(
				resolving: resolver,
				origin: resolved.origin,
				visited: visited.union([resolved.identity])
			)
			overlays.append(imported.document)
			conflicts.append(contentsOf: imported.conflicts)
		}
		local.imports.removeAll()

		for connection in connections {
			let resolved: ResolvedLexiconImport?
			do {
				resolved = try resolve(connection.import, using: resolver, relativeTo: origin)
			} catch {
				conflicts.append(.init(
					kind: .importResolution,
					path: connection.path.description,
					existing: "load failed",
					incoming: error.localizedDescription
				))
				continue
			}
			guard let resolved else {
				conflicts.append(.init(
					kind: .importResolution,
					path: connection.path.description,
					existing: "unresolved",
					incoming: connection.import.reference
				))
				continue
			}
			guard !visited.contains(resolved.identity) else {
				conflicts.append(.init(
					kind: .importResolution,
					path: connection.path.description,
					existing: "import cycle",
					incoming: resolved.identity
				))
				continue
			}
			let imported = try resolved.document.composed(
				resolving: resolver,
				origin: resolved.origin,
				visited: visited.union([resolved.identity])
			)
			conflicts.append(contentsOf: imported.conflicts)
			do {
				overlays.append(try imported.document.grafted(onto: connection.path))
				try local.removeConnection(connection.import, at: connection.path)
			} catch {
				conflicts.append(.init(
					kind: .invalidGraft,
					path: connection.path.description,
					existing: connection.import.reference,
					incoming: error.localizedDescription
				))
			}
		}

		// Imports are overlays in declaration order. The source is deliberately
		// last, so local declarations beat every imported value.
		overlays.append(local)
		let merged = Self.merge(overlays)
		return .init(
			document: merged.document,
			conflicts: conflicts
		)
	}

	func resolve(
		_ import: Lexicon.Import,
		using resolver: LexiconImportResolving,
		relativeTo origin: URL?
	) throws -> ResolvedLexiconImport? {
		if let resolver = resolver as? any ContextualLexiconImportResolving {
			return try resolver.resolve(`import`, relativeTo: origin)
		}
		return try resolver.resolve(`import`).map {
			.init(
				document: $0,
				origin: nil,
				identity: `import`.reference
			)
		}
	}

	var connections: [(path: Lemma.ID, import: Lexicon.Import)] {
		roots.flatMap { rootName, root in
			var result: [(path: Lemma.ID, import: Lexicon.Import)] = []
			root.traverse(id: Lemma.ID(root: rootName)) { id, _, node in
				for `import` in node.connections {
					result.append((id, `import`))
				}
			}
			return result
		}
	}

	func grafted(onto anchorID: Lemma.ID) throws -> Self {
		guard roots.count == 1, let sourceRootName = roots.keys.first,
			let sourceRoot = roots[sourceRootName]
		else {
			throw LexiconError(
				"A node-level import must resolve to exactly one explicit root"
			)
		}
		let sourceID = Lemma.ID(root: sourceRootName)
		let leaf = sourceRoot.rewritingInternalReferences(
			from: sourceID,
			to: anchorID,
			oldPath: sourceID,
			newPath: anchorID
		)
		return .init(
			date: date,
			roots: [anchorID.root: Self.scaffold(path: anchorID.components, leaf: leaf)],
			notes: notes,
			comments: comments
		)
	}

	static func scaffold(
		path: [Lemma.Name],
		leaf: Lexicon.Graph.Node
	) -> Lexicon.Graph.Node {
		guard path.count > 1 else {
			return leaf
		}
		var node = leaf
		for index in stride(from: path.count - 2, through: 0, by: -1) {
			node = .init(children: [path[index + 1]: node])
		}
		return node
	}

	mutating func removeConnection(
		_ import: Lexicon.Import,
		at path: Lemma.ID
	) throws {
		guard var root = roots[path.root] else {
			throw LexiconError("Could not find root '\(path.root)'")
		}
		try root.mergeMutate(path: path.components.dropFirst()) { node in
			node.connections.removeAll { $0 == `import` }
		}
		roots[path.root] = root
	}

	mutating func overlay(_ incoming: Self) {
		date = incoming.date
		imports.append(contentsOf: incoming.imports)
		notes.append(contentsOf: incoming.notes)
		comments.append(contentsOf: incoming.comments)

		for (name, node) in incoming.roots {
			if let existing = roots[name] {
				roots[name] = existing.overlaying(node)
			} else {
				roots[name] = node
			}
		}
	}
}

private extension Lexicon.Graph.Node {

	func overlaying(_ incoming: Self) -> Self {
		var result = self
		result.type = incoming.type
		result.protonym = incoming.protonym
		if let defaultValue = incoming.defaultValue {
			result.defaultValue = defaultValue
		}
		result.connections.append(contentsOf: incoming.connections)
		result.notes.append(contentsOf: incoming.notes)
		result.comments.append(contentsOf: incoming.comments)

		if incoming.protonym != nil {
			result.type.removeAll()
			result.children.removeAll()
			return result
		}

		for (name, child) in incoming.children {
			if let existing = result.children[name] {
				result.children[name] = existing.overlaying(child)
			} else {
				result.children[name] = child
			}
		}
		return result
	}

	mutating func mergeMutate<Path>(
		path: Path,
		_ body: (inout Self) throws -> Void
	) throws where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw LexiconError("Could not find lemma path component '\(name)'")
		}
		try child.mergeMutate(path: path.dropFirst(), body)
		children[name] = child
	}
}

private extension FileLexiconImportResolver {

	func resolved(
		_ import: Lexicon.Import,
		relativeTo origin: URL?
	) throws -> ResolvedLexiconImport? {
		let url: URL
		if let origin, !origin.isFileURL {
			guard allowRemote else {
				return nil
			}
			guard let candidate = URL(
				string: `import`.reference,
				relativeTo: origin
			)?.absoluteURL else {
				return nil
			}
			guard candidate.hasSameOrigin(as: origin) else {
				throw LexiconError(
					"Nested remote import '\(candidate)' crosses origin '\(origin)'"
				)
			}
			url = candidate
		} else {
			switch `import`.location {
				case .local:
					let parent = origin?.isFileURL == true
						? origin!.deletingLastPathComponent()
						: baseURL
					guard let candidate = localURL(
						for: `import`.reference,
						relativeTo: parent
					) else {
						return nil
					}
					url = candidate
				case .remote:
					guard
						allowRemote,
						let remote = URL(string: `import`.reference),
						["http", "https"].contains(remote.scheme?.lowercased())
					else {
						return nil
					}
					url = remote
			}
		}
		if url.isFileURL {
			let document = try TaskPaper(Data(contentsOf: url)).decodeDocument()
			return .init(
				document: document,
				origin: url,
				identity: url.lexiconImportIdentity
			)
		}

		let allowedRedirectOrigin = origin?.isFileURL == false ? origin : nil
		let response = try RemoteImportLoader.load(
			url,
			allowedRedirectOrigin: allowedRedirectOrigin
		)
		let document = try TaskPaper(response.data).decodeDocument()
		return .init(
			document: document,
			origin: response.url,
			identity: response.url.lexiconImportIdentity
		)
	}

	func localURL(for reference: String, relativeTo parent: URL) -> URL? {
		let base = baseURL.standardizedFileURL.resolvingSymlinksInPath()
		let candidate = URL(fileURLWithPath: reference, relativeTo: parent)
			.standardizedFileURL
			.resolvingSymlinksInPath()
		guard candidate.isFileURL else {
			return nil
		}
		guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else {
			return nil
		}
		return candidate
	}
}

extension URL {

	var lexiconImportIdentity: String {
		if isFileURL {
			return standardizedFileURL.resolvingSymlinksInPath().absoluteString
		}
		return absoluteURL.absoluteString
	}

	func hasSameOrigin(as other: URL) -> Bool {
		guard
			let lhsScheme = scheme?.lowercased(),
			let rhsScheme = other.scheme?.lowercased(),
			let lhsHost = host?.lowercased(),
			let rhsHost = other.host?.lowercased()
		else {
			return false
		}
		return lhsScheme == rhsScheme &&
			lhsHost == rhsHost &&
			effectivePort == other.effectivePort
	}

	var effectivePort: Int? {
		if let port {
			return port
		}
		switch scheme?.lowercased() {
			case "http": return 80
			case "https": return 443
			default: return nil
		}
	}
}

enum RemoteImportLoader {

	struct Response {
		var data: Data
		var url: URL
	}

	static func load(
		_ url: URL,
		allowedRedirectOrigin: URL?,
		maximumResponseBytes: Int =
			FileLexiconImportResolver.maximumRemoteResponseBytes,
		configuration suppliedConfiguration: URLSessionConfiguration? = nil
	) throws -> Response {
		precondition(maximumResponseBytes >= 0)
		let state = RequestState()
		let completion = DispatchSemaphore(value: 0)
		let delegate = DataDelegate(
			allowedOrigin: allowedRedirectOrigin,
			maximumResponseBytes: maximumResponseBytes,
			state: state,
			completion: completion
		)
		let configuration = suppliedConfiguration ?? .ephemeral
		configuration.timeoutIntervalForRequest = 30
		configuration.timeoutIntervalForResource = 60
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		let session = URLSession(
			configuration: configuration,
			delegate: delegate,
			delegateQueue: nil
		)
		var request = URLRequest(
			url: url,
			cachePolicy: .reloadIgnoringLocalCacheData,
			timeoutInterval: 30
		)
		request.httpShouldHandleCookies = false

		session.dataTask(with: request).resume()

		completion.wait()
		session.finishTasksAndInvalidate()

		if let blockedRedirect = state.blockedRedirect {
			throw LexiconError(
				"Remote import redirect to '\(blockedRedirect)' crosses the allowed origin"
			)
		}
		switch state.result {
			case .success(let response):
				return response
			case .failure(let message):
				throw LexiconError(message)
			case nil:
				throw LexiconError("Remote import completed without a result")
		}
	}

	static func redirectIsAllowed(
		to redirectedURL: URL,
		allowedOrigin: URL?
	) -> Bool {
		guard let allowedOrigin else {
			return true
		}
		return redirectedURL.hasSameOrigin(as: allowedOrigin)
	}

	private final class RequestState: @unchecked Sendable {
		private let lock = NSLock()
		private var storedResult: Result?
		private var storedBlockedRedirect: URL?
		private var responseData = Data()
		private var responseURL: URL?

		var result: Result? {
			lock.withLock { storedResult }
		}

		var blockedRedirect: URL? {
			lock.withLock { storedBlockedRedirect }
		}

		func complete(_ result: Result) {
			lock.withLock {
				if storedResult == nil {
					storedResult = result
				}
			}
		}

		func blockRedirect(_ url: URL) {
			lock.withLock {
				storedBlockedRedirect = url
			}
		}

		func beginResponse(at url: URL) {
			lock.withLock {
				responseURL = url
			}
		}

		func append(
			_ data: Data,
			maximumResponseBytes: Int
		) -> Bool {
			lock.withLock {
				guard storedResult == nil else {
					return false
				}
				guard data.count <= maximumResponseBytes - responseData.count else {
					storedResult = .failure(
						RemoteImportLoader.oversizeMessage(maximumResponseBytes)
					)
					return false
				}
				responseData.append(data)
				return true
			}
		}

		func finishResponse() {
			lock.withLock {
				guard storedResult == nil else {
					return
				}
				guard let responseURL else {
					storedResult = .failure("Remote import returned no HTTP response.")
					return
				}
				storedResult = .success(.init(data: responseData, url: responseURL))
			}
		}
	}

	private enum Result {
		case success(Response)
		case failure(String)
	}

	private static func oversizeMessage(_ maximumResponseBytes: Int) -> String {
		"Remote import exceeds the maximum response size of \(maximumResponseBytes) bytes."
	}

	private final class DataDelegate: NSObject, URLSessionDataDelegate,
		@unchecked Sendable {

		let allowedOrigin: URL?
		let maximumResponseBytes: Int
		let state: RequestState
		let completion: DispatchSemaphore

		init(
			allowedOrigin: URL?,
			maximumResponseBytes: Int,
			state: RequestState,
			completion: DispatchSemaphore
		) {
			self.allowedOrigin = allowedOrigin
			self.maximumResponseBytes = maximumResponseBytes
			self.state = state
			self.completion = completion
		}

		func urlSession(
			_ session: URLSession,
			dataTask: URLSessionDataTask,
			didReceive response: URLResponse,
			completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
		) {
			guard
				let response = response as? HTTPURLResponse,
				let finalURL = response.url
			else {
				state.complete(.failure("Remote import returned no HTTP response."))
				completionHandler(.cancel)
				return
			}
			guard (200..<300).contains(response.statusCode) else {
				state.complete(.failure(
					"Remote import returned HTTP status \(response.statusCode)."
				))
				completionHandler(.cancel)
				return
			}
			guard ["http", "https"].contains(finalURL.scheme?.lowercased()) else {
				state.complete(.failure(
					"Remote import resolved to unsupported URL '\(finalURL)'."
				))
				completionHandler(.cancel)
				return
			}
			guard RemoteImportLoader.redirectIsAllowed(
				to: finalURL,
				allowedOrigin: allowedOrigin
			) else {
				state.complete(.failure(
					"Remote import redirected across origin to '\(finalURL)'."
				))
				completionHandler(.cancel)
				return
			}
			guard
				response.expectedContentLength < 0 ||
				response.expectedContentLength <= Int64(maximumResponseBytes)
			else {
				state.complete(.failure(
					RemoteImportLoader.oversizeMessage(maximumResponseBytes)
				))
				completionHandler(.cancel)
				return
			}
			state.beginResponse(at: finalURL)
			completionHandler(.allow)
		}

		func urlSession(
			_ session: URLSession,
			dataTask: URLSessionDataTask,
			didReceive data: Data
		) {
			guard state.append(
				data,
				maximumResponseBytes: maximumResponseBytes
			) else {
				dataTask.cancel()
				return
			}
		}

		func urlSession(
			_ session: URLSession,
			task: URLSessionTask,
			didCompleteWithError error: (any Error)?
		) {
			if let error {
				state.complete(.failure(error.localizedDescription))
			} else {
				state.finishResponse()
			}
			completion.signal()
		}

		func urlSession(
			_ session: URLSession,
			task: URLSessionTask,
			willPerformHTTPRedirection response: HTTPURLResponse,
			newRequest request: URLRequest,
			completionHandler: @escaping (URLRequest?) -> Void
		) {
			guard
				let redirectedURL = request.url,
				!RemoteImportLoader.redirectIsAllowed(
					to: redirectedURL,
					allowedOrigin: allowedOrigin
				)
			else {
				completionHandler(request)
				return
			}
			state.blockRedirect(redirectedURL)
			completionHandler(nil)
		}
	}
}

extension Lexicon.Graph.Node.DefaultValue: CustomStringConvertible {

	public var description: String {
		switch self {
			case .literal(let value):
				return value.description
			case .reference(let id):
				return "@ \(id)"
		}
	}
}

extension JSONValue: CustomStringConvertible {

	public var description: String {
		switch self {
			case .string(let value):
				return value
			case .number(let value):
				return "\(value)"
			case .bool(let value):
				return "\(value)"
			case .array(let value):
				return "[" + value.map(\.description).joined(separator: ", ") + "]"
			case .object(let value):
				return "{" + value.sorted(by: { $0.key < $1.key })
					.map { "\($0.key): \($0.value)" }
					.joined(separator: ", ") + "}"
			case .null:
				return "null"
		}
	}
}
