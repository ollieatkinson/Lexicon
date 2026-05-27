import ArgumentParser
import Foundation
import Lexicon

@main
struct LexiconCommand: AsyncParsableCommand {

	static let configuration = CommandConfiguration(
		commandName: "lexicon",
		abstract: "A script-friendly utility for working with lexicon documents.",
		version: "1.0.0",
		subcommands: [
			Validate.self,
			Lint.self,
			Inspect.self,
			Tree.self,
			Search.self,
			SearchEvaluate.self,
			Refs.self,
			Excerpt.self,
			Format.self,
			Diff.self,
			Add.self,
			Remove.self,
			Rename.self,
			Move.self,
			SetType.self,
			UnsetType.self,
			SetProtonym.self,
			SetDefault.self,
			Note.self,
			Comment.self,
			Interactive.self,
		]
	)
}
