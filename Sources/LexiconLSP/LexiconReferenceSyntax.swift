//
// github.com/screensailor 2026
//

import Foundation
import Lexicon

struct LocatedLexiconPath {
	var path: String
	var range: LexiconTextRange
}

struct LexiconPrefixContext {
	var rawPrefix: String
	var prefixes: [String]
}

struct CompletionContext {
	var prefixes: [String]
	var replacementRange: LexiconTextRange

	init?(text: String, line: Int, character: Int) {
		guard let cursor = text.index(line: line, utf16Character: character) else {
			return nil
		}
		let beforeCursor = text[..<cursor]
		let codeContext = CodeReferenceSyntax.all
			.compactMap { $0.prefixContext(beforeCursor: beforeCursor) }
			.min { $0.rawPrefix.utf16.count < $1.rawPrefix.utf16.count }
		guard let context = codeContext ?? LexiconDocumentSyntax.prefixContext(beforeCursor: beforeCursor) else {
			return nil
		}
		self.prefixes = context.prefixes
		let partial = LexiconPathIndex.split(context.rawPrefix).partial
		let start = text.index(cursor, offsetByUTF16: -partial.utf16.count) ?? cursor
		self.replacementRange = LexiconTextRange(
			start: text.position(for: start),
			end: text.position(for: cursor)
		)
	}
}

struct CodeReferenceSyntax: Sendable {
	static var all: [Self] {
		[quotedCall, rust]
	}

	static let quotedCall = CodeReferenceSyntax(
		name: "Quoted l call",
		opening: #"l(""#,
		path: .quotedString,
		references: { text in
			text.locatedLexiconPaths(matching: #/(?:^|[^A-Za-z0-9_])l\("(?<path>[^"\\]*(?:\\.[^"\\]*)*)"\)/#)
		},
		completionTerminators: ["\n", "\""]
	)

	static let rust = CodeReferenceSyntax(
		name: "Rust",
		opening: "l!(",
		path: .dottedIdentifier,
		references: { text in
			text.locatedLexiconPaths(matching: #/(?:^|[^A-Za-z0-9_])l!\((?<path>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\)/#)
		},
		completionTerminators: ["\n", ")"]
	)

	var name: String
	var opening: String
	var path: CodeReferencePathSyntax
	var references: @Sendable (String) -> [LocatedLexiconPath]
	var completionTerminators: Set<Character>

	func prefixContext(beforeCursor text: Substring) -> LexiconPrefixContext? {
		var searchEnd = text.endIndex
		while let openingRange = text[..<searchEnd].range(of: opening, options: .backwards) {
			defer { searchEnd = openingRange.lowerBound }
			guard isOpeningBoundary(in: text, at: openingRange.lowerBound) else {
				continue
			}
			let rawPrefix = text[openingRange.upperBound...]
			guard
				rawPrefix.contains(where: completionTerminators.contains) == false,
				path.acceptsCompletionPrefix(rawPrefix)
			else {
				return nil
			}
			let prefix = String(rawPrefix)
			return LexiconPrefixContext(rawPrefix: prefix, prefixes: [prefix])
		}
		return nil
	}

	private func isOpeningBoundary(in text: Substring, at index: String.Index) -> Bool {
		guard index > text.startIndex else {
			return true
		}
		return text[text.index(before: index)].isASCIIIdentifierContinuation == false
	}
}

struct CodeReferencePathSyntax: Sendable {
	var acceptsCompletionPrefix: @Sendable (Substring) -> Bool
}

extension CodeReferencePathSyntax {
	static let quotedString = Self(
		acceptsCompletionPrefix: { _ in true }
	)

	static let dottedIdentifier = Self(
		acceptsCompletionPrefix: { prefix in
			var expectsSegmentStart = true
			for character in prefix {
				if character == "." {
					guard expectsSegmentStart == false else {
						return false
					}
					expectsSegmentStart = true
				} else if expectsSegmentStart {
					guard character.isASCIIIdentifierStart else {
						return false
					}
					expectsSegmentStart = false
				} else {
					guard character.isASCIIIdentifierContinuation else {
						return false
					}
				}
			}
			return true
		}
	)
}

struct LexiconDocumentSyntax {
	static func prefixContext(beforeCursor text: Substring) -> LexiconPrefixContext? {
		guard let reference = LexiconDocumentReferencePrefix(beforeCursor: text) else {
			return nil
		}
		let prefixes: [String]
		if
			reference.kind == .protonym,
			let ownerPath = reference.ownerPath,
			let parent = parentPath(for: ownerPath)
		{
			prefixes = ["\(parent).\(reference.rawPrefix)"]
		} else if reference.kind == .protonym {
			prefixes = []
		} else {
			prefixes = [reference.rawPrefix]
		}
		return LexiconPrefixContext(rawPrefix: reference.rawPrefix, prefixes: prefixes)
	}

	static func references(in text: String, index: LexiconPathIndex) -> [LocatedLexiconPath] {
		let result = TaskPaper(text).parse()
		var ranges = LexiconDocumentSourceMap(sourceMap: result.sourceMap, text: text)
		return LexiconDocumentReference.references(in: result.document, index: index).compactMap { reference in
			ranges.range(for: reference).map {
				LocatedLexiconPath(path: reference.validationPath, range: $0)
			}
		}
	}

	static func syntaxDiagnostics(in text: String) -> [LexiconDiagnostic] {
		TaskPaper(text).parse().diagnostics
			.filter { !isIncompleteReference($0, in: text) }
			.map(LexiconDiagnostic.init)
	}

	private static func parentPath(for path: String) -> String? {
		let components = path.components(separatedBy: ".").dropLast()
		guard components.isEmpty == false else {
			return nil
		}
		return components.joined(separator: ".")
	}

	private static func isIncompleteReference(
		_ diagnostic: Lexicon.Diagnostic,
		in text: String
	) -> Bool {
		guard
			diagnostic.code == .invalidReference,
			let range = diagnostic.sourceRange
		else {
			return false
		}
		let offsets = range.utf16Offsets
		guard
			offsets.lowerBound >= 0,
			offsets.upperBound <= text.utf16.count,
			let start = String.Index(
				text.utf16.index(text.utf16.startIndex, offsetBy: offsets.lowerBound),
				within: text
			),
			let end = String.Index(
				text.utf16.index(text.utf16.startIndex, offsetBy: offsets.upperBound),
				within: text
			)
		else {
			return false
		}
		return text[start..<end]
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.hasSuffix(".")
	}
}

struct LexiconDocumentReferencePrefix {
	private static let sentinel = "lexicon_lsp_probe"

	var kind: LexiconDocumentReference.Kind
	var rawPrefix: String
	var ownerPath: String?

	init?(beforeCursor text: Substring) {
		let cursorOffset = text.utf16.count
		guard
			let line = TaskPaper("\(text)\(Self.sentinel)").sourceMap().references.last(where: { line in
				line.referenceRange?.contains(cursorOffset) == true
			}),
			var rawPrefix = line.reference,
			rawPrefix.hasSuffix(Self.sentinel)
		else {
			return nil
		}
		rawPrefix.removeLast(Self.sentinel.count)
		switch line.content {
		case .lemma:
			return nil
		case .type:
			self.kind = .type
		case .protonym:
			self.kind = .protonym
		case .defaultReference:
			self.kind = .defaultValue
		}
		self.rawPrefix = rawPrefix
		self.ownerPath = line.nodePath
	}
}

struct LexiconDocumentReference: Hashable {
	struct Kind: Hashable, Sendable {
		static let type = Self("type")
		static let protonym = Self("protonym")
		static let defaultValue = Self("defaultValue")

		var rawValue: String

		init(_ rawValue: String) {
			self.rawValue = rawValue
		}
	}

	struct SourceKey: Hashable {
		var ownerPath: String
		var kind: Kind
		var rawPath: String

		init(ownerPath: String, kind: Kind, rawPath: String) {
			self.ownerPath = ownerPath
			self.kind = kind
			self.rawPath = rawPath
		}

		init?(_ line: TaskPaper.SourceMap.Line) {
			guard let ownerPath = line.nodePath, let rawPath = line.reference else {
				return nil
			}
			let kind: Kind
			switch line.content {
			case .lemma:
				return nil
			case .type:
				kind = .type
			case .protonym:
				kind = .protonym
			case .defaultReference:
				kind = .defaultValue
			}
			self.init(ownerPath: ownerPath, kind: kind, rawPath: rawPath)
		}
	}

	var ownerPath: String
	var kind: Kind
	var rawPath: String
	var validationPath: String

	var sourceKey: SourceKey {
		SourceKey(ownerPath: ownerPath, kind: kind, rawPath: rawPath)
	}

	static func references(in document: Lexicon.Document, index: LexiconPathIndex) -> [Self] {
		var references: [Self] = []
		for (rootName, root) in document.roots {
			root.traverse(id: Lemma.ID(root: rootName)) { id, _, node in
				let ownerPath = id.description
				for type in node.type.sorted() {
					let rawPath = type.description
					references.append(Self(
						ownerPath: ownerPath,
						kind: .type,
						rawPath: rawPath,
						validationPath: rawPath
					))
				}
				if let protonym = node.protonym {
					let rawPath = protonym.description
					references.append(Self(
						ownerPath: ownerPath,
						kind: .protonym,
						rawPath: rawPath,
						validationPath: index.resolvedProtonym(
							rawPath,
							fromParentOf: ownerPath
						) ?? index.relativePath(rawPath, fromParentOf: ownerPath)
					))
				}
				if case .reference(let reference) = node.defaultValue {
					let rawPath = reference.description
					references.append(Self(
						ownerPath: ownerPath,
						kind: .defaultValue,
						rawPath: rawPath,
						validationPath: rawPath
					))
				}
			}
		}
		return references
	}
}

struct LexiconDocumentSourceMap {
	private var ranges: [LexiconDocumentReference.SourceKey: [LexiconTextRange]] = [:]

	init(sourceMap: TaskPaper.SourceMap, text: String) {
		for line in sourceMap.references {
			guard
				let sourceKey = LexiconDocumentReference.SourceKey(line),
				let referenceRange = line.referenceRange
			else {
				continue
			}
			ranges[sourceKey, default: []].append(LexiconTextRange(
				start: text.position(forUTF16Offset: referenceRange.lowerBound),
				end: text.position(forUTF16Offset: referenceRange.upperBound)
			))
		}
	}

	mutating func range(for reference: LexiconDocumentReference) -> LexiconTextRange? {
		guard var ranges = ranges[reference.sourceKey], ranges.isEmpty == false else {
			return nil
		}
		let range = ranges.removeFirst()
		self.ranges[reference.sourceKey] = ranges
		return range
	}
}

extension Character {
	var isASCIIIdentifierStart: Bool {
		guard unicodeScalars.count == 1, let value = unicodeScalars.first?.value else {
			return false
		}
		return value == 95 || (65...90).contains(value) || (97...122).contains(value)
	}

	var isASCIIIdentifierContinuation: Bool {
		guard unicodeScalars.count == 1, let value = unicodeScalars.first?.value else {
			return false
		}
		return isASCIIIdentifierStart || (48...57).contains(value)
	}
}

extension String {
	func locatedLexiconPaths(
		matching regex: Regex<(Substring, path: Substring)>
	) -> [LocatedLexiconPath] {
		matches(of: regex).map { match in
			let substring = match.output.path
			return LocatedLexiconPath(
				path: String(substring),
				range: LexiconTextRange(
					start: position(for: substring.startIndex),
					end: position(for: substring.endIndex)
				)
			)
		}
	}
}

extension LexiconPathIndex {
	func resolvedProtonym(_ reference: String, fromParentOf path: String) -> String? {
		let relative = relativePath(reference, fromParentOf: path)
		return contains(relative) ? relative : nil
	}

	func relativePath(_ reference: String, fromParentOf path: String) -> String {
		let parent = path.components(separatedBy: ".").dropLast().joined(separator: ".")
		return parent.isEmpty ? reference : "\(parent).\(reference)"
	}
}

private extension LexiconDiagnostic {
	init(_ diagnostic: Lexicon.Diagnostic) {
		let range: LexiconTextRange
		if let sourceRange = diagnostic.sourceRange {
			range = LexiconTextRange(
				start: LexiconPosition(
					line: sourceRange.lowerBound.line,
					character: sourceRange.lowerBound.utf16Column
				),
				end: LexiconPosition(
					line: sourceRange.upperBound.line,
					character: sourceRange.upperBound.utf16Column
				)
			)
		} else {
			range = LexiconTextRange(
				start: LexiconPosition(line: 0, character: 0),
				end: LexiconPosition(line: 0, character: 0)
			)
		}
		self.init(range: range, message: diagnostic.message)
	}
}
