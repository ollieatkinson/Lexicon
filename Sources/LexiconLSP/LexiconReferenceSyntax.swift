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
		[go, rust]
	}

	static let go = CodeReferenceSyntax(
		name: "Go",
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
		var prefixes = [reference.rawPrefix]
		if let ownerPath = reference.ownerPath, let parent = parentPath(for: ownerPath) {
			prefixes.append("\(parent).\(reference.rawPrefix)")
		}
		return LexiconPrefixContext(rawPrefix: reference.rawPrefix, prefixes: prefixes)
	}

	static func references(in text: String, index: LexiconPathIndex) -> [LocatedLexiconPath] {
		let taskPaper = TaskPaper(text)
		guard
			let document = try? taskPaper.decodeDocument(),
			let sourceMap = try? taskPaper.sourceMap()
		else {
			return []
		}
		var ranges = LexiconDocumentSourceMap(sourceMap: sourceMap, text: text)
		return LexiconDocumentReference.references(in: document, index: index).compactMap { reference in
			ranges.range(for: reference).map {
				LocatedLexiconPath(path: reference.validationPath, range: $0)
			}
		}
	}

	static func indentationDiagnostics(in text: String) -> [LexiconDiagnostic] {
		var diagnostics: [LexiconDiagnostic] = []
		var utf16Offset = 0
		for lineText in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
			defer { utf16Offset += lineText.utf16.count + 1 }
			let leadingWhitespace = lineText.prefix { $0 == "\t" || $0 == " " }
			let leadingTabs = leadingWhitespace.prefix { $0 == "\t" }
			guard leadingTabs.count < leadingWhitespace.count else {
				continue
			}
			let startOffset = utf16Offset + leadingTabs.utf16.count
			let endOffset = utf16Offset + leadingWhitespace.utf16.count
			diagnostics.append(LexiconDiagnostic(
				range: LexiconTextRange(
					start: text.position(forUTF16Offset: startOffset),
					end: text.position(forUTF16Offset: endOffset)
				),
				message: "Lexicon indentation uses tabs; spaces are ignored for hierarchy."
			))
		}
		return diagnostics
	}

	private static func parentPath(for path: String) -> String? {
		let components = path.components(separatedBy: ".").dropLast()
		guard components.isEmpty == false else {
			return nil
		}
		return components.joined(separator: ".")
	}
}

struct LexiconDocumentReferencePrefix {
	private static let sentinel = "__lexicon_lsp_probe__"

	var kind: LexiconDocumentReference.Kind
	var rawPrefix: String
	var ownerPath: String?

	init?(beforeCursor text: Substring) {
		let cursorOffset = text.utf16.count
		guard
			let line = try? TaskPaper("\(text)\(Self.sentinel)").sourceMap().references.last(where: { line in
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
		for root in document.roots.values {
			root.traverse { id, _, node in
				for type in node.type.sorted() {
					references.append(Self(
						ownerPath: id,
						kind: .type,
						rawPath: type,
						validationPath: index.resolved(type, fromParentOf: id) ?? type
					))
				}
				if let protonym = node.protonym {
					references.append(Self(
						ownerPath: id,
						kind: .protonym,
						rawPath: protonym,
						validationPath: index.resolvedProtonym(protonym, fromParentOf: id)
							?? index.relativePath(protonym, fromParentOf: id)
					))
				}
				if case .reference(let reference) = node.defaultValue {
					references.append(Self(
						ownerPath: id,
						kind: .defaultValue,
						rawPath: reference,
						validationPath: index.resolved(reference, fromParentOf: id) ?? reference
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
	func resolved(_ reference: String, fromParentOf path: String) -> String? {
		if contains(reference) {
			return reference
		}
		let relative = relativePath(reference, fromParentOf: path)
		return contains(relative) ? relative : nil
	}

	func resolvedProtonym(_ reference: String, fromParentOf path: String) -> String? {
		let relative = relativePath(reference, fromParentOf: path)
		return contains(relative) ? relative : nil
	}

	func relativePath(_ reference: String, fromParentOf path: String) -> String {
		let parent = path.components(separatedBy: ".").dropLast().joined(separator: ".")
		return parent.isEmpty ? reference : "\(parent).\(reference)"
	}
}
