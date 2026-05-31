//
// github.com/screensailor 2026
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum RustStandAloneGenerator: SourceCodeGenerator {

	public static let utType = UTType(filenameExtension: "rs", conformingTo: .sourceCode)!
	public static let command = "rust"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.rust()
	}
}

private extension Lexicon.Graph.JSON {

	func rust() throws -> String {
		try SourceTemplate(
			"""
			#![allow(non_camel_case_types)]
			#![allow(non_snake_case)]

			pub trait I {
				fn id(&self) -> &str;
				fn localized(&self) -> &str;
			}

			#[derive(Clone, Debug, Eq, PartialEq, Hash)]
			pub struct L {
				id: String,
			}

			impl L {
				pub fn new(id: impl Into<String>) -> Self {
					Self { id: id.into() }
				}
			}

			impl I for L {
				fn id(&self) -> &str {
					&self.id
				}

				fn localized(&self) -> &str {
					&self.id
				}
			}

			#[derive(Clone, Debug, Eq, PartialEq, Hash)]
			pub struct Lexicon {
				pub {{rootField}}: {{rootType}},
			}

			impl Lexicon {
				pub fn new() -> Self {
					Self {
						{{rootField}}: {{rootType}}::new("{{rootID}}"),
					}
				}

				pub fn {{rootFunction}}(&self) -> {{rootType}} {
					self.{{rootField}}.clone()
				}
			}

			impl Default for Lexicon {
				fn default() -> Self {
					Self::new()
				}
			}

			pub fn l() -> Lexicon {
				Lexicon::new()
			}

			pub fn {{rootFunction}}() -> {{rootType}} {
				{{rootType}}::new("{{rootID}}")
			}

			macro_rules! __lexicon_l {
				(@path [$($lexicon_path:tt)*]) => {
					$($lexicon_path)*
				};
			{{macroTailKeywordArms}}
				(@path [$($lexicon_path:tt)*] . $segment:ident $(.$tail:tt)*) => {
					l!(@path [$($lexicon_path)*.$segment()] $(.$tail)*)
				};
				(@path [$($lexicon_path:tt)*] $($path:tt)+) => {
					compile_error!(concat!("invalid Lexicon path syntax: ", stringify!($($path)+)))
				};
			{{macroRootKeywordArms}}
				($root:ident $(.$tail:tt)*) => {
					l!(@path [l().$root()] $(.$tail)*)
				};
				($($path:tt)*) => {
					compile_error!(concat!("invalid Lexicon path syntax: ", stringify!($($path)*)))
				};
			}

			pub(crate) use __lexicon_l as l;

			{{types}}

			"""
		).render([
			"rootField": try name.rustSelector(),
			"rootFunction": try name.rustSelector(),
			"rootType": name.rustTypeName,
			"rootID": name.rustStringLiteralContent,
			"macroRootKeywordArms": rustMacroRootKeywordArms(),
			"macroTailKeywordArms": rustMacroTailKeywordArms(),
			"types": try classes.flatMap { try $0.rust(classes: classes) }.joined(separator: "\n\n"),
		])
	}

	func rustMacroRootKeywordArms() -> String {
		rustMacroRootKeywords
			.map { keyword in
				"""
					(\(keyword) $(.$tail:tt)*) => {
						l!(@path [l().r#\(keyword)()] $(.$tail)*)
					};
				"""
			}
			.joined(separator: "\n")
	}

	func rustMacroTailKeywordArms() -> String {
		rustMacroTailKeywords
			.map { keyword in
				"""
					(@path [$($lexicon_path:tt)*] . \(keyword) $(.$tail:tt)*) => {
						l!(@path [$($lexicon_path)*.r#\(keyword)()] $(.$tail)*)
					};
				"""
			}
			.joined(separator: "\n")
	}

	var rustMacroRootKeywords: [String] {
		[name.rustIdentifier]
			.filter(\.isRustRawIdentifierKeyword)
	}

	var rustMacroTailKeywords: [String] {
		Array(Set(
			classes
				.flatMap { $0.standAloneAllAccessors(classes: classes) }
				.map(\.name.rustIdentifier)
				.filter(\.isRustRawIdentifierKeyword)
		))
		.sorted()
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func rust(classes: [Lexicon.Graph.Node.Class.JSON]) throws -> [String] {
		guard mixin == nil else {
			return []
		}

		let type = id.rustTypeName

		if let protonym = protonym {
			return [
				try SourceTemplate("pub type {{type}} = {{protonym}};").render([
					"type": type,
					"protonym": protonym.rustTypeName,
				])
			]
		}

		let ownAccessors = standAloneAccessors()
		return [
			try SourceTemplate(
				"""
				#[derive(Clone, Debug, Eq, PartialEq, Hash)]
				pub struct {{type}} {
					l: L,{{fields}}
				}

				impl {{type}} {
					pub fn new(id: impl Into<String>) -> Self {
						let id = id.into();
						Self {
							l: L::new(id.clone()),{{initializers}}
						}
					}{{inherited}}
				}

				impl I for {{type}} {
					fn id(&self) -> &str {
						I::id(&self.l)
					}

					fn localized(&self) -> &str {
						"{{localized}}"
					}
				}
				"""
			).render([
				"type": type,
				"localized": id.rustStringLiteralContent,
				"fields": ownAccessors
					.map { accessor in
						"\n\tpub \(try accessor.name.rustSelector()): \(accessor.sourceID.rustTypeName),"
					}
					.joined(),
				"initializers": ownAccessors
					.map { accessor in
						"\n\t\t\t\(try accessor.name.rustSelector()): \(accessor.factory(receiver: "id")),"
					}
					.joined(),
				"inherited": try ownAccessors
					.map { try $0.ownMethod() }
					.joined() + standAloneInheritedAccessors(classes: classes)
					.filter { inherited in !ownAccessors.contains(where: { $0.name == inherited.name }) }
					.map { try $0.method(receiverType: type) }
					.joined(),
			])
		]
	}
}

private extension StandAloneAccessor {

	func factory(receiver: String) -> String {
		"\(targetID.rustTypeName)::new(format!(\"{}.\(pathSuffix.rustStringLiteralContent)\", \(receiver)))"
	}

	func ownMethod() throws -> String {
		try "\n\n" + SourceTemplate(
			"""
			\tpub fn {{name}}(&self) -> {{sourceType}} {
			\t\tself.{{name}}.clone()
			\t}
			"""
		).render([
			"name": name.rustSelector(),
			"sourceType": sourceID.rustTypeName,
		])
	}

	func method(receiverType: String) throws -> String {
		"\n\n" + (try SourceTemplate(
			"""
			\tpub fn {{name}}(&self) -> {{sourceType}} {
			\t\t{{factory}}
			\t}
			"""
		).render([
			"name": try name.rustSelector(),
			"sourceType": sourceID.rustTypeName,
			"factory": factory(receiver: "I::id(self)"),
		]))
	}
}

private extension String {

	var rustTypeName: String {
		"L_" + split(separator: ".")
			.map(String.init)
			.map(\.rustTypeSegment)
			.joined(separator: "_")
	}

	var rustTypeSegment: String {
		rustIdentifier.replacingOccurrences(of: "_", with: "__")
	}

	var rustIdentifier: String {
		let sanitized = map { character -> Character in
			character.isLetter || character.isNumber || character == "_" ? character : "_"
		}
		var identifier = String(sanitized).unlessEmpty ?? "lexicon"
		if identifier.first?.isNumber == true {
			identifier = "_\(identifier)"
		}
		return identifier
	}

	func rustSelector() throws -> String {
		let identifier = rustIdentifier
		if identifier.isRustPathKeyword {
			throw RustGenerationError.unsupportedPathKeyword(identifier)
		}
		if identifier.isRustKeyword {
			return "r#\(identifier)"
		}
		return identifier
	}

	var rustStringLiteralContent: String {
		map { character -> String in
			switch character {
			case "\\":
				return "\\\\"
			case "\"":
				return "\\\""
			case "\n":
				return "\\n"
			case "\r":
				return "\\r"
			case "\t":
				return "\\t"
			default:
				return String(character)
			}
		}
		.joined()
	}

	var isRustPathKeyword: Bool {
		switch self {
		case "crate", "self", "super", "Self":
			return true
		default:
			return false
		}
	}

	var isRustKeyword: Bool {
		Self.rustKeywords.contains(self)
	}

	var isRustRawIdentifierKeyword: Bool {
		isRustKeyword && !isRustPathKeyword
	}

	static let rustKeywords = [
		"abstract",
		"as",
		"async",
		"await",
		"become",
		"box",
		"break",
		"const",
		"continue",
		"crate",
		"do",
		"dyn",
		"else",
		"enum",
		"extern",
		"false",
		"final",
		"fn",
		"for",
		"gen",
		"if",
		"impl",
		"in",
		"let",
		"loop",
		"macro",
		"match",
		"mod",
		"move",
		"mut",
		"override",
		"priv",
		"pub",
		"ref",
		"return",
		"self",
		"Self",
		"static",
		"struct",
		"super",
		"trait",
		"true",
		"try",
		"type",
		"typeof",
		"union",
		"unsafe",
		"unsized",
		"use",
		"virtual",
		"where",
		"while",
		"yield",
	]
}

private enum RustGenerationError: Error, CustomStringConvertible {
	case unsupportedPathKeyword(String)

	var description: String {
		switch self {
		case .unsupportedPathKeyword(let keyword):
			"""
			Rust cannot generate exact member syntax for '\(keyword)' \
			because Rust reserves it even for raw identifiers.
			"""
		}
	}
}
