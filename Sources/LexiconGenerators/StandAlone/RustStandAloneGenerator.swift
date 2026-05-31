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
			{{macroArms}}
				($($path:tt)*) => {
					compile_error!(concat!("unknown Lexicon path: ", stringify!($($path)*)))
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
			"macroArms": try rustMacroArms(),
			"types": try classes.flatMap { try $0.rust(classes: classes) }.joined(separator: "\n\n"),
		])
	}

	func rustMacroArms() throws -> String {
		try RustMacroPathBuilder(rootID: name, classes: classes)
			.paths()
			.map { path in
				try SourceTemplate(
					"""
						({{macroPath}}) => {
							{{expression}}
						};
					"""
				).render([
					"macroPath": path.path,
					"expression": path.expression,
				])
			}
			.joined(separator: "\n")
	}
}

private struct RustMacroPath {
	var path: String
	var expression: String
}

private struct RustMacroPathBuilder {
	var rootID: String
	var classes: [Lexicon.Graph.Node.Class.JSON]

	private var classesByID: [String: Lexicon.Graph.Node.Class.JSON] {
		Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
	}

	func paths() throws -> [RustMacroPath] {
		var output: [String: String] = [:]
		try emit(
			path: rootID,
			sourceID: rootID,
			expression: "l().\(rootID.rustSelector())",
			active: [],
			into: &output
		)
		return output
			.map { RustMacroPath(path: $0.key, expression: $0.value) }
			.sorted { $0.path < $1.path }
	}

	private func emit(
		path: String,
		sourceID: String,
		expression: String,
		active: Set<String>,
		into output: inout [String: String]
	) throws {
		output[path] = expression
		guard active.contains(sourceID) == false, let klass = classesByID[sourceID] else {
			return
		}
		let active = active.union([sourceID])
		let ownAccessors = klass.standAloneAccessors()
		let ownNames = Set(ownAccessors.map(\.name))
		for accessor in ownAccessors.sorted(by: { $0.name < $1.name }) {
			try emit(accessor, from: path, expression: expression, isMethod: false, active: active, into: &output)
		}
		for accessor in klass.standAloneInheritedAccessors(classes: classes)
			.filter({ ownNames.contains($0.name) == false })
			.sorted(by: { $0.name < $1.name })
		{
			try emit(accessor, from: path, expression: expression, isMethod: true, active: active, into: &output)
		}
	}

	private func emit(
		_ accessor: StandAloneAccessor,
		from path: String,
		expression: String,
		isMethod: Bool,
		active: Set<String>,
		into output: inout [String: String]
	) throws {
		let selector = try accessor.name.rustSelector()
		try emit(
			path: "\(path).\(accessor.name)",
			sourceID: accessor.isSynonym ? accessor.targetID : accessor.sourceID,
			expression: isMethod ? "\(expression).\(selector)()" : "\(expression).\(selector)",
			active: active,
			into: &output
		)
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
				"inherited": try standAloneInheritedAccessors(classes: classes)
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
		switch self {
		case "as", "break", "const", "continue", "crate", "else", "enum",
			"extern", "false", "fn", "for", "if", "impl", "in", "let",
			"loop", "match", "mod", "move", "mut", "pub", "ref", "return",
			"self", "Self", "static", "struct", "super", "trait", "true",
			"type", "unsafe", "use", "where", "while", "async", "await",
			"dyn", "abstract", "become", "box", "do", "final", "macro",
			"override", "priv", "typeof", "unsized", "virtual", "yield",
			"try", "union", "gen":
			return true
		default:
			return false
		}
	}
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
