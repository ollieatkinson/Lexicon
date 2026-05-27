//
// github.com/screensailor 2026
//

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public extension Lexicon {

	enum SearchMode: String, Codable, Hashable, Sendable {
		case lexical
		case token
		case semantic
		case hybrid
	}

	enum SearchScope: String, Codable, Hashable, Sendable {
		case own
		case live
		case full
	}

	enum SearchField: String, Codable, Hashable, Sendable {
		case id
		case name
		case type
		case protonym
		case defaultReference
		case defaultLiteral
		case note
		case comment
		case connection
		case ancestor
		case contextChild
	}

	struct SearchBounds: Hashable, Sendable {
		public static let defaultDepth = Int.max
		public static let defaultCandidates = 100
		public static let defaultBudget = 50_000

		public var depth: Int
		public var candidates: Int
		public var budget: Int

		public init(
			depth: Int = Self.defaultDepth,
			candidates: Int = Self.defaultCandidates,
			budget: Int = Self.defaultBudget
		) {
			self.depth = depth
			self.candidates = candidates
			self.budget = budget
		}
	}

	struct SearchOptions: Hashable, Sendable {
		public var limit: Int
		public var root: Lemma.ID?
		public var mode: SearchMode
		public var scope: SearchScope
		public var includeReferences: Bool
		public var includeMetadata: Bool
		public var includeDefaults: Bool
		public var includeConnections: Bool
		public var semanticThreshold: Double
		public var bounds: SearchBounds

		public init(
			limit: Int = 50,
			root: Lemma.ID? = nil,
			mode: SearchMode = .hybrid,
			scope: SearchScope = .own,
			includeReferences: Bool = true,
			includeMetadata: Bool = true,
			includeDefaults: Bool = true,
			includeConnections: Bool = true,
			semanticThreshold: Double = 0.42,
			bounds: SearchBounds = .init()
		) {
			self.limit = limit
			self.root = root
			self.mode = mode
			self.scope = scope
			self.includeReferences = includeReferences
			self.includeMetadata = includeMetadata
			self.includeDefaults = includeDefaults
			self.includeConnections = includeConnections
			self.semanticThreshold = semanticThreshold
			self.bounds = bounds
		}
	}

	struct SearchEmbeddingDescriptor: Codable, Hashable, Sendable {
		public var provider: String
		public var model: String
		public var modelRevision: String?
		public var tokenizer: String
		public var dimensions: Int?
		public var normalized: Bool
		public var pooling: String

		public init(
			provider: String,
			model: String,
			modelRevision: String? = nil,
			tokenizer: String,
			dimensions: Int? = nil,
			normalized: Bool,
			pooling: String
		) {
			self.provider = provider
			self.model = model
			self.modelRevision = modelRevision
			self.tokenizer = tokenizer
			self.dimensions = dimensions
			self.normalized = normalized
			self.pooling = pooling
		}

		public var identifier: String {
			[
				provider,
				model,
				modelRevision ?? "default",
				tokenizer,
				dimensions.map(String.init) ?? "unknown-dimensions",
				normalized ? "normalized" : "raw",
				pooling,
			].joined(separator: "/")
		}
	}

	struct SearchEmbeddingCache: Codable, Hashable, Sendable {
		public var version: Int
		public var descriptor: SearchEmbeddingDescriptor
		public var fingerprint: String
		public var vectors: [Lemma.ID: [Double]]

		public init(
			version: Int = 2,
			descriptor: SearchEmbeddingDescriptor,
			fingerprint: String,
			vectors: [Lemma.ID: [Double]]
		) {
			self.version = version
			self.descriptor = descriptor
			self.fingerprint = fingerprint
			self.vectors = vectors
		}
	}

	protocol SearchEmbeddingProvider: Sendable {
		var descriptor: SearchEmbeddingDescriptor { get }
		func embed(_ texts: [String]) async throws -> [[Double]]
	}

	struct SearchScores: Codable, Hashable, Sendable {
		public var lexical: Double
		public var token: Double
		public var semantic: Double?
		public var total: Double

		public init(lexical: Double, token: Double, semantic: Double?, total: Double) {
			self.lexical = lexical
			self.token = token
			self.semantic = semantic
			self.total = total
		}
	}

	struct SearchResult: Codable, Hashable, Sendable {
		public var id: Lemma.ID
		public var name: Lemma.Name
		public var score: Double
		public var scores: SearchScores
		public var matches: [Match]
		public var type: [Lemma.ID]
		public var protonym: Lemma.ID?
		public var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
		public var notes: [String]
		public var comments: [String]
		public var children: [Lemma.Name]

		public init(
			id: Lemma.ID,
			name: Lemma.Name,
			score: Double,
			scores: SearchScores,
			matches: [Match],
			type: [Lemma.ID],
			protonym: Lemma.ID?,
			defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?,
			notes: [String],
			comments: [String],
			children: [Lemma.Name]
		) {
			self.id = id
			self.name = name
			self.score = score
			self.scores = scores
			self.matches = matches
			self.type = type
			self.protonym = protonym
			self.defaultValue = defaultValue
			self.notes = notes
			self.comments = comments
			self.children = children
		}
	}
}

public extension Lexicon.SearchResult {

	struct Match: Codable, Hashable, Sendable {
		public var field: Lexicon.SearchField
		public var term: String
		public var value: String
		public var kind: String

		public init(field: Lexicon.SearchField, term: String, value: String, kind: String) {
			self.field = field
			self.term = term
			self.value = value
			self.kind = kind
		}
	}
}

public extension Lexicon.Document {

	func search(_ query: String, options: Lexicon.SearchOptions = .init()) -> [Lexicon.SearchResult] {
		Lexicon.SearchIndex(document: self, options: options).search(query)
	}

	func search<Terms>(_ terms: Terms, options: Lexicon.SearchOptions = .init()) -> [Lexicon.SearchResult]
	where Terms: Collection, Terms.Element == String {
		search(terms.joined(separator: " "), options: options)
	}
}

public extension Lexicon.SearchEmbeddingProvider {

	var identifier: String {
		descriptor.identifier
	}
}

public extension Lexicon {

	struct SearchIndex: Sendable {
		public var entries: [SearchEntry]
		public var options: SearchOptions
		public var fingerprint: String {
			var hash = StableHash()
			for entry in entries.sorted(by: { $0.id < $1.id }) {
				hash.append(entry.id)
				hash.append(entry.embeddingText)
			}
			return hash.hex
		}

		public init(document: Lexicon.Document, options: SearchOptions = .init()) {
			self.options = options
			self.entries = document.searchEntries(options: options)
		}

		public init(entries: [SearchEntry], options: SearchOptions = .init()) {
			self.options = options
			self.entries = entries
		}

		public func search(
			_ query: String,
			embeddingCache: SearchEmbeddingCache? = nil,
			queryVector: [Double]? = nil
		) -> [SearchResult] {
			let query = SearchQuery(query)
			guard query.hasTerms, options.limit != 0 else {
				return []
			}

			let queryVector = queryVector ?? (options.mode.usesSemanticSearch
				? SemanticEmbedding.vector(for: query.embeddingText)
				: nil)
			let results = entries.compactMap { entry in
				let entryVector = embeddingCache?.vectors[entry.id]
					?? (queryVector?.isEmpty == false ? SemanticEmbedding.vector(for: entry.embeddingText) : nil)
				return entry.result(
					for: query,
					queryVector: queryVector,
					entryVector: entryVector,
					options: options
				)
			}
			let sorted = results.sorted {
				if $0.score == $1.score {
					return $0.id < $1.id
				}
				return $0.score > $1.score
			}

			guard options.limit > 0 else {
				return sorted
			}
			return Array(sorted.prefix(options.limit))
		}

		public func search(
			_ rawQuery: String,
			in document: Lexicon.Document,
			embeddingCache: SearchEmbeddingCache? = nil,
			queryVector: [Double]? = nil
		) async throws -> [SearchResult] {
			switch options.scope {
				case .own:
					return search(rawQuery, embeddingCache: embeddingCache, queryVector: queryVector)
				case .live:
					let context = try await liveSearchContext(
						rawQuery,
						document: document,
						embeddingCache: embeddingCache,
						queryVector: queryVector
					)
					return rankedContextResults(
						query: context.query,
						queryVector: queryVector,
						ownResults: context.ownResults,
						contextEntries: context.contextEntries,
						contextVectors: [:]
					)
				case .full:
					let index = try await materialized(in: document)
					let cache = embeddingCache?.fingerprint == index.fingerprint ? embeddingCache : nil
					return index.search(rawQuery, embeddingCache: cache, queryVector: queryVector)
			}
		}

		public func search<Provider: SearchEmbeddingProvider>(
			_ rawQuery: String,
			in document: Lexicon.Document,
			embeddingCache: SearchEmbeddingCache? = nil,
			queryVector: [Double]? = nil,
			contextEmbeddingProvider provider: Provider
		) async throws -> [SearchResult] {
			switch options.scope {
				case .own:
					return search(rawQuery, embeddingCache: embeddingCache, queryVector: queryVector)
				case .live:
					let context = try await liveSearchContext(
						rawQuery,
						document: document,
						embeddingCache: embeddingCache,
						queryVector: queryVector
					)
					let contextVectors = try await embeddingVectors(for: context.contextEntries, using: provider)
					return rankedContextResults(
						query: context.query,
						queryVector: queryVector,
						ownResults: context.ownResults,
						contextEntries: context.contextEntries,
						contextVectors: contextVectors
					)
				case .full:
					let index = try await materialized(in: document)
					let cache: SearchEmbeddingCache?
					if embeddingCache?.fingerprint == index.fingerprint {
						cache = embeddingCache
					} else if options.mode.usesSemanticSearch {
						cache = try await index.embeddingCache(using: provider)
					} else {
						cache = nil
					}
					return index.search(rawQuery, embeddingCache: cache, queryVector: queryVector)
			}
		}

		public func materialized(in document: Lexicon.Document) async throws -> SearchIndex {
			guard options.scope == .full else {
				return self
			}
			var materializedOptions = options
			materializedOptions.scope = .own
			let entries = try await resolvedSearchEntries(in: document)
			return .init(
				entries: entries,
				options: materializedOptions
			)
		}

		public func embeddingCache<Provider: SearchEmbeddingProvider>(
			using provider: Provider
		) async throws -> SearchEmbeddingCache {
			let entries = entries.sorted { $0.id < $1.id }
			let vectors = try await embeddingVectors(for: entries, using: provider)
			return .init(
				descriptor: provider.descriptor,
				fingerprint: fingerprint,
				vectors: vectors
			)
		}

		private func liveSearchContext(
			_ rawQuery: String,
			document: Lexicon.Document,
			embeddingCache: SearchEmbeddingCache?,
			queryVector: [Double]?
		) async throws -> (query: SearchQuery, ownResults: [SearchResult], contextEntries: [SearchEntry]) {
			let query = SearchQuery(rawQuery)
			guard query.hasTerms, options.limit != 0 else {
				return (query, [], [])
			}

			var candidateOptions = options
			candidateOptions.scope = .own
			candidateOptions.limit = max(1, options.bounds.candidates)
			let candidateIndex = SearchIndex(document: document, options: candidateOptions)
			let ownResults = candidateIndex.search(
				rawQuery,
				embeddingCache: embeddingCache,
				queryVector: queryVector
			)
			let projectedEntries = try await contextEntries(in: document, seedResults: ownResults)
			return (query, ownResults, projectedEntries)
		}

		private func rankedContextResults(
			query: SearchQuery,
			queryVector: [Double]?,
			ownResults: [SearchResult],
			contextEntries: [SearchEntry],
			contextVectors: [Lemma.ID: [Double]]
		) -> [SearchResult] {
			let queryVector = queryVector ?? self.queryVector(for: query)
			let contextResults = contextEntries.compactMap { entry in
				let entryVector = contextVectors[entry.id]
					?? (queryVector?.isEmpty == false ? SemanticEmbedding.vector(for: entry.embeddingText) : nil)
				return entry.result(
					for: query,
					queryVector: queryVector,
					entryVector: entryVector,
					options: options
				)
			}
			let sorted = (ownResults + contextResults)
				.reduce(into: [Lemma.ID: SearchResult]()) { results, result in
					guard let existing = results[result.id] else {
						results[result.id] = result
						return
					}
					if result.score >= existing.score {
						results[result.id] = result
					}
				}
				.values
				.sorted {
					if $0.score == $1.score {
						return $0.id < $1.id
					}
					return $0.score > $1.score
				}

			guard options.limit > 0 else {
				return sorted
			}
			return Array(sorted.prefix(options.limit))
		}

		private func queryVector(for query: SearchQuery) -> [Double]? {
			options.mode.usesSemanticSearch ? SemanticEmbedding.vector(for: query.embeddingText) : nil
		}

		private func embeddingVectors<Provider: SearchEmbeddingProvider>(
			for entries: [SearchEntry],
			using provider: Provider
		) async throws -> [Lemma.ID: [Double]] {
			var vectors: [Lemma.ID: [Double]] = [:]
			for batch in entries.chunks(ofCount: 32) {
				let embeddings = try await provider.embed(batch.map { "search_document: \($0.embeddingText)" })
				for (entry, vector) in zip(batch, embeddings) {
					vectors[entry.id] = vector
				}
			}
			return vectors
		}

		@LexiconActor private func contextEntries(
			in document: Lexicon.Document,
			seedResults: [SearchResult]
		) async throws -> [SearchEntry] {
			guard seedResults.isNotEmpty else {
				return []
			}
			let rootName = options.root?
				.split(separator: ".", maxSplits: 1)
				.first
				.map(String.init)
			let lexicon = try Lexicon.from(document, root: rootName)
			let entryIDs = Set(entries.map(\.id))
			let seedIDs = seedResults
				.prefix(max(1, options.bounds.candidates))
				.map(\.id)
			let seedIDSet = Set(seedIDs)
			var selected: [Lemma.ID] = []
			var seen: Set<Lemma.ID> = []

			func add(_ id: Lemma.ID) {
				guard entryIDs.contains(id), seen.insert(id).inserted else {
					return
				}
				selected.append(id)
			}

			for id in seedIDs {
				add(id)
				for ancestor in id.ancestorIDs.dropLast().reversed() {
					add(ancestor)
				}
			}

			for entry in entries where selected.count < options.bounds.candidates {
				let isRelated = entry.type.contains { typeID in
					seedIDSet.contains { seedID in
						seedID.isSameOrDescendant(of: typeID) || typeID.isSameOrDescendant(of: seedID)
					}
				}
				if isRelated {
					add(entry.id)
				}
			}

			var budget = max(0, options.bounds.budget)
			var entries: [SearchEntry] = []
			for id in selected.prefix(max(1, options.bounds.candidates)) {
				guard budget > 0, let lemma = lexicon[id] else {
					continue
				}
				entries.append(lemma.contextSearchEntry(
					options: options,
					depth: max(0, options.bounds.depth),
					budget: &budget
				))
			}
			return entries
		}

		@LexiconActor private func resolvedSearchEntries(in document: Lexicon.Document) throws -> [SearchEntry] {
			let rootName = options.root?
				.split(separator: ".", maxSplits: 1)
				.first
				.map(String.init)
			let lexicon = try Lexicon.from(document, root: rootName)
			let roots: [Lemma]
			if let root = options.root {
				roots = lexicon[root].map { [$0] } ?? []
			} else {
				roots = Array(lexicon.roots.values)
			}

			let maxDepth = max(0, options.bounds.depth)
			let childContextDepth = min(maxDepth, 1)
			let childContextBudget = max(0, min(options.bounds.budget, 1_024))
			var remaining = max(0, options.bounds.budget)
			var entries: [SearchEntry] = []
			var seenEntries: Set<Lemma.ID> = []

			for root in roots {
				root.searchTraversal(depth: maxDepth, budget: &remaining) { lemma, _ in
					guard seenEntries.insert(lemma.id).inserted else {
						return
					}
					var fieldBudget = childContextBudget
					entries.append(lemma.contextSearchEntry(
						options: options,
						depth: childContextDepth,
						budget: &fieldBudget
					))
				}
			}

			return entries
		}
	}

	struct SearchEntry: Hashable, Sendable {
		public var id: Lemma.ID
		public var name: Lemma.Name
		public var fields: [SearchDocument]
		public var type: [Lemma.ID]
		public var protonym: Lemma.ID?
		public var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
		public var notes: [String]
		public var comments: [String]
		public var children: [Lemma.Name]

		public init(
			id: Lemma.ID,
			name: Lemma.Name,
			fields: [SearchDocument],
			type: [Lemma.ID],
			protonym: Lemma.ID?,
			defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?,
			notes: [String],
			comments: [String],
			children: [Lemma.Name]
		) {
			self.id = id
			self.name = name
			self.fields = fields
			self.type = type
			self.protonym = protonym
			self.defaultValue = defaultValue
			self.notes = notes
			self.comments = comments
			self.children = children
		}
	}

	struct SearchDocument: Hashable, Sendable {
		public var field: SearchField
		public var value: String
		public var weight: Double
		public var tokens: [String]
		public var tokenSet: Set<String>
		public var normalizedText: String

		public init(field: SearchField, value: String, weight: Double) {
			let tokens = SearchTokenizer.tokens(in: value)
			self.field = field
			self.value = value
			self.weight = weight
			self.tokens = tokens
			self.tokenSet = Set(tokens)
			self.normalizedText = tokens.joined(separator: " ")
		}
	}
}

public extension Lexicon.SearchEntry {

	var embeddingText: String {
		fields
			.map(\.normalizedText)
			.filter(\.isNotEmpty)
			.joined(separator: " ")
	}
}

private extension Lexicon.Document {

	func searchEntries(options: Lexicon.SearchOptions) -> [Lexicon.SearchEntry] {
		var entries: [Lexicon.SearchEntry] = []
		for root in roots.values {
			root.traverse { id, _, node in
				guard options.root.map({ id.isSameOrDescendant(of: $0) }) ?? true else {
					return
				}
				entries.append(node.searchEntry(id: id, options: options))
			}
		}
		return entries
	}
}

private extension Lexicon.Graph.Node {

	var searchSignature: String {
		let defaultSignature: String
		switch defaultValue {
			case .reference(let id):
				defaultSignature = "reference:\(id)"
			case .literal(let value):
				defaultSignature = "literal:\(value.searchText)"
			case nil:
				defaultSignature = ""
		}
		return [
			name,
			protonym ?? "",
			type.sorted().joined(separator: "|"),
			defaultSignature,
			children.keys.joined(separator: "|"),
		].joined(separator: ":")
	}

	func searchEntry(id: String, options: Lexicon.SearchOptions) -> Lexicon.SearchEntry {
		var fields = [
			Lexicon.SearchDocument(field: .id, value: id, weight: 6.0),
			Lexicon.SearchDocument(field: .name, value: name, weight: 8.0),
		]

		if options.includeReferences {
			fields.append(contentsOf: type.sorted().map {
				Lexicon.SearchDocument(field: .type, value: $0, weight: 4.0)
			})
			if let protonym {
				fields.append(.init(field: .protonym, value: protonym, weight: 4.0))
			}
		}

		if options.includeDefaults, let defaultValue {
			switch defaultValue {
				case .reference(let id):
					fields.append(.init(field: .defaultReference, value: id, weight: 4.0))
				case .literal(let value):
					fields.append(.init(field: .defaultLiteral, value: value.searchText, weight: 1.5))
			}
		}

		if options.includeMetadata {
			fields.append(contentsOf: notes.map {
				Lexicon.SearchDocument(field: .note, value: $0, weight: 2.5)
			})
			fields.append(contentsOf: comments.map {
				Lexicon.SearchDocument(field: .comment, value: $0, weight: 1.5)
			})
		}

		if options.includeConnections {
			fields.append(contentsOf: connections.map {
				Lexicon.SearchDocument(field: .connection, value: $0.reference, weight: 2.0)
			})
		}

		return .init(
			id: id,
			name: name,
			fields: fields,
			type: type.sorted(),
			protonym: protonym,
			defaultValue: defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init),
			notes: notes,
			comments: comments,
			children: Array(children.keys)
		)
	}
}

private extension Lemma {

	var searchTraversalKey: String {
		if isGraphNode {
			return "graph:\(id)"
		}
		return "inherited:\(node.searchSignature)"
	}

	func searchTraversal(
		depth: Int,
		budget: inout Int,
		_ yield: (Lemma, Int) -> Void
	) {
		func walk(_ lemma: Lemma, level: Int, remainingDepth: Int, lineage: Set<String>) {
			guard budget > 0 else {
				return
			}

			budget -= 1
			yield(lemma, level)

			guard remainingDepth > 0 else {
				return
			}

			let nextDepth = remainingDepth == Int.max ? Int.max : remainingDepth - 1
			for child in lemma.children.values {
				let key = child.searchTraversalKey
				guard !lineage.contains(key) else {
					continue
				}
				var lineage = lineage
				lineage.insert(key)
				walk(
					child,
					level: level + 1,
					remainingDepth: nextDepth,
					lineage: lineage
				)
			}
		}

		walk(self, level: 0, remainingDepth: max(0, depth), lineage: [searchTraversalKey])
	}

	func contextSearchEntry(
		options: Lexicon.SearchOptions,
		depth: Int,
		budget: inout Int
	) -> Lexicon.SearchEntry {
		let base = node.searchEntry(id: id, options: options)
		var fields = base.fields

		for ancestor in id.ancestorIDs.dropLast() {
			fields.append(.init(field: .ancestor, value: ancestor, weight: 2.5))
		}

		let resolvedType = Array(type.keys).sorted()
		if options.includeReferences {
			for typeID in resolvedType where !base.type.contains(typeID) {
				fields.append(.init(field: .type, value: typeID, weight: 3.5))
			}
			let sourceID = source.id
			if sourceID != id {
				fields.append(.init(field: .protonym, value: sourceID, weight: 3.5))
			}
		}

		if options.includeDefaults, let defaultValue {
			fields.append(defaultValue.searchDocument(weight: 3.0))
		}

		var resolvedChildren = Array(children.keys)
		searchTraversal(depth: depth, budget: &budget) { child, level in
			guard level > 0 else {
				return
			}
			resolvedChildren.append(child.name)
			let sourceID = child.source.id
			let value = sourceID == child.id
				? "\(child.id) \(child.name)"
				: "\(child.id) \(child.name) \(sourceID)"
			fields.append(.init(
				field: .contextChild,
				value: value,
				weight: max(1.0, 3.5 / Double(level))
			))
		}

		return .init(
			id: id,
			name: name,
			fields: fields.uniqued(),
			type: resolvedType,
			protonym: protonym?.unwrapped.id,
			defaultValue: defaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init),
			notes: node.notes,
			comments: node.comments,
			children: resolvedChildren.uniqued()
		)
	}
}

private extension Lexicon.Graph.Node.DefaultValue {

	func searchDocument(weight: Double) -> Lexicon.SearchDocument {
		switch self {
			case .reference(let id):
				return .init(field: .defaultReference, value: id, weight: weight)
			case .literal(let value):
				return .init(field: .defaultLiteral, value: value.searchText, weight: weight)
		}
	}
}

private extension Lexicon.SearchEntry {

	func result(
		for query: SearchQuery,
		queryVector: [Double]?,
		entryVector: [Double]?,
		options: Lexicon.SearchOptions
	) -> Lexicon.SearchResult? {
		let lexical = options.mode.usesLexicalSearch ? lexicalScore(for: query) : .empty
		let token = options.mode.usesTokenSearch ? tokenScore(for: query) : .empty
		let semantic = options.mode.usesSemanticSearch
			? semanticScore(queryVector: queryVector, entryVector: entryVector)
			: nil

		let semanticAccepted = semantic.map { $0 >= options.semanticThreshold } ?? false
		let tokenAccepted = token.matchedTerms.isSuperset(of: query.tokens)
		let lexicalAccepted = lexical.score > 0

		let accepted: Bool
		switch options.mode {
			case .lexical:
				accepted = lexicalAccepted
			case .token:
				accepted = tokenAccepted
			case .semantic:
				accepted = semanticAccepted
			case .hybrid:
				accepted = tokenAccepted || semanticAccepted || lexicalAccepted
		}
		guard accepted else {
			return nil
		}

		let semanticScore = semantic.map { $0 * 1000 }
		let total = lexical.score + token.score + (semanticScore ?? 0)
		let scores = Lexicon.SearchScores(
			lexical: lexical.score,
			token: token.score,
			semantic: semantic,
			total: total
		)

		var matches = (lexical.matches + token.matches).uniqued()
		if semantic != nil, semanticAccepted {
			matches.append(.init(field: .id, term: query.raw, value: embeddingText, kind: "semantic"))
		}

		return .init(
			id: id,
			name: name,
			score: total,
			scores: scores,
			matches: matches,
			type: type,
			protonym: protonym,
			defaultValue: defaultValue,
			notes: notes,
			comments: comments,
			children: children
		)
	}

	func lexicalScore(for query: SearchQuery) -> SearchScore {
		var score = 0.0
		var matches: [Lexicon.SearchResult.Match] = []
		let phrase = query.normalizedPhrase

		for field in fields {
			guard field.normalizedText.isNotEmpty else {
				continue
			}
			if field.normalizedText == phrase {
				score += field.weight * 160
				matches.append(.init(field: field.field, term: query.raw, value: field.value, kind: "exactPhrase"))
			} else if field.normalizedText.hasPrefix(phrase) {
				score += field.weight * 110
				matches.append(.init(field: field.field, term: query.raw, value: field.value, kind: "prefixPhrase"))
			} else if field.normalizedText.contains(phrase) {
				score += field.weight * 75
				matches.append(.init(field: field.field, term: query.raw, value: field.value, kind: "containsPhrase"))
			}

			let similarity = field.normalizedText.ngramSimilarity(to: phrase)
			if similarity >= 0.34 {
				score += field.weight * similarity * 45
				matches.append(.init(field: field.field, term: query.raw, value: field.value, kind: "ngram"))
			}
		}

		return .init(score: score, matchedTerms: [], matches: matches)
	}

	func tokenScore(for query: SearchQuery) -> SearchScore {
		var score = 0.0
		var matchedTerms: Set<String> = []
		var matches: [Lexicon.SearchResult.Match] = []

		for token in query.tokens {
			var best: (score: Double, match: Lexicon.SearchResult.Match)?
			for field in fields {
				guard let candidate = field.bestMatch(for: token) else {
					continue
				}
				if best.map({ candidate.score > $0.score }) ?? true {
					best = (candidate.score, .init(
						field: field.field,
						term: token,
						value: field.value,
						kind: candidate.kind
					))
				}
			}
			if let best {
				matchedTerms.insert(token)
				score += best.score
				matches.append(best.match)
			}
		}

		if matchedTerms.isSuperset(of: query.tokens), query.tokens.count > 1 {
			score += 100
		}

		return .init(score: score, matchedTerms: matchedTerms, matches: matches)
	}

	func semanticScore(queryVector: [Double]?, entryVector: [Double]?) -> Double? {
		guard let queryVector, queryVector.isNotEmpty else {
			return nil
		}
		let entryVector = entryVector ?? SemanticEmbedding.vector(for: embeddingText)
		guard let entryVector else {
			return nil
		}
		return queryVector.cosineSimilarity(to: entryVector)
	}
}

private extension Lexicon.SearchDocument {

	func bestMatch(for queryToken: String) -> (score: Double, kind: String)? {
		var best: (score: Double, kind: String)?

		for token in tokenSet {
			let score: Double?
			let kind: String
			if token == queryToken {
				score = weight * 100
				kind = "token"
			} else if token.hasPrefix(queryToken) || queryToken.hasPrefix(token) {
				score = weight * 68
				kind = "prefixToken"
			} else if token.contains(queryToken) || queryToken.contains(token) {
				score = weight * 32
				kind = "containsToken"
			} else {
				let similarity = token.ngramSimilarity(to: queryToken)
				if similarity >= 0.58 {
					score = weight * similarity * 44
					kind = "tokenNgram"
				} else {
					score = nil
					kind = ""
				}
			}

			guard let score else {
				continue
			}
			if best.map({ score > $0.score }) ?? true {
				best = (score, kind)
			}
		}
		return best
	}
}

private struct SearchQuery {
	var raw: String
	var tokens: Set<String>
	var normalizedPhrase: String
	var embeddingText: String

	init(_ raw: String) {
		self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		let tokens = SearchTokenizer.tokens(in: raw)
		self.tokens = Set(tokens)
		self.normalizedPhrase = tokens.joined(separator: " ")
		self.embeddingText = normalizedPhrase
	}

	var hasTerms: Bool {
		tokens.isNotEmpty
	}
}

private struct SearchScore {
	var score: Double
	var matchedTerms: Set<String>
	var matches: [Lexicon.SearchResult.Match]

	static let empty = SearchScore(score: 0, matchedTerms: [], matches: [])
}

private enum SearchTokenizer {

	private static let separators = CharacterSet.alphanumerics.inverted

	static func tokens(in string: String) -> [String] {
		let splitCamel = string.splittingCamelCase()
		let base = splitCamel
			.components(separatedBy: separators)
			.compactMap { word -> String? in
				let word = word.lowercased()
				guard word.isNotEmpty else {
					return nil
				}
				return word
			}
		return base.uniqued()
	}
}

private enum SemanticEmbedding {

	static func vector(for text: String) -> [Double]? {
		let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard text.isNotEmpty else {
			return nil
		}
		#if canImport(NaturalLanguage)
		return NLEmbedding.sentenceEmbedding(for: .english)?.vector(for: text)
		#else
		return nil
		#endif
	}
}

private extension Lexicon.SearchMode {

	var usesLexicalSearch: Bool {
		switch self {
			case .lexical, .hybrid:
				return true
			case .token, .semantic:
				return false
		}
	}

	var usesTokenSearch: Bool {
		switch self {
			case .token, .hybrid:
				return true
			case .lexical, .semantic:
				return false
		}
	}

	var usesSemanticSearch: Bool {
		switch self {
			case .semantic, .hybrid:
				return true
			case .lexical, .token:
				return false
		}
	}
}

private extension String {

	func splittingCamelCase() -> String {
		var output = ""
		var previous: Character?
		for character in self {
			if
				let previous,
				character.isUppercase,
				previous.isLowercase || previous.isNumber
			{
				output.append(" ")
			}
			output.append(character)
			previous = character
		}
		return output
	}

	func ngramSimilarity(to other: String, size: Int = 3) -> Double {
		let left = ngrams(size: size)
		let right = other.ngrams(size: size)
		guard left.isNotEmpty, right.isNotEmpty else {
			return self == other ? 1 : 0
		}
		let intersection = left.intersection(right).count
		let union = left.union(right).count
		return union == 0 ? 0 : Double(intersection) / Double(union)
	}

	func ngrams(size: Int) -> Set<String> {
		let value = lowercased()
		guard value.count >= size else {
			return value.isEmpty ? [] : [value]
		}
		var grams: Set<String> = []
		var index = value.startIndex
		while let end = value.index(index, offsetBy: size, limitedBy: value.endIndex) {
			grams.insert(String(value[index..<end]))
			index = value.index(after: index)
		}
		return grams
	}

	func isSameOrDescendant(of ancestor: String) -> Bool {
		self == ancestor || hasPrefix("\(ancestor).")
	}

	var ancestorIDs: [String] {
		let parts = split(separator: ".").map(String.init)
		guard parts.isNotEmpty else {
			return []
		}
		return parts.indices.map { index in
			parts[...index].joined(separator: ".")
		}
	}
}

private extension JSONValue {

	var searchText: String {
		switch self {
			case .string(let value):
				return value
			case .number(let value):
				return String(value)
			case .bool(let value):
				return String(value)
			case .array(let values):
				return values.map(\.searchText).joined(separator: " ")
			case .object(let object):
				return object
					.sorted { $0.key < $1.key }
					.map { "\($0.key) \($0.value.searchText)" }
					.joined(separator: " ")
			case .null:
				return "null"
		}
	}
}

private extension Array where Element == Double {

	func cosineSimilarity(to other: [Double]) -> Double {
		guard count == other.count else {
			return 0
		}
		var dot = 0.0
		var left = 0.0
		var right = 0.0
		for (l, r) in zip(self, other) {
			dot += l * r
			left += l * l
			right += r * r
		}
		guard left > 0, right > 0 else {
			return 0
		}
		return dot / (left.squareRoot() * right.squareRoot())
	}
}

private extension Array {

	func chunks(ofCount count: Int) -> [[Element]] {
		guard count > 0 else {
			return [self]
		}
		var chunks: [[Element]] = []
		var index = startIndex
		while index < endIndex {
			let end = self.index(index, offsetBy: count, limitedBy: endIndex) ?? endIndex
			chunks.append(Array(self[index..<end]))
			index = end
		}
		return chunks
	}
}

private struct StableHash {
	private var value: UInt64 = 0xcbf29ce484222325

	mutating func append(_ string: String) {
		for byte in string.utf8 {
			value ^= UInt64(byte)
			value &*= 0x100000001b3
		}
		value ^= 0xff
		value &*= 0x100000001b3
	}

	var hex: String {
		String(value, radix: 16)
	}
}
