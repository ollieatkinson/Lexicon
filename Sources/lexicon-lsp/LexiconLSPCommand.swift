//
// github.com/screensailor 2026
//

import ArgumentParser
import Foundation

@main
struct LexiconLSPCommand: ParsableCommand {

	static let configuration = CommandConfiguration(
		commandName: "lexicon-lsp",
		abstract: "A language server for Lexicon path completions and diagnostics.",
		version: "1.0.0"
	)

	@Option(help: "Root lexicon path. Workspace config is used when omitted.")
	var lexicon: URL?

	@Flag(help: "Use stdio transport. This is the default and is accepted for editor client compatibility.")
	var stdio = false

	func run() throws {
		LexiconLanguageServer(
			workspace: LexiconWorkspace(explicitLexiconURL: lexicon?.standardizedFileURL)
		).run()
	}
}

#if compiler(>=6.0)
extension URL: @retroactive ExpressibleByArgument {

	public init?(argument: String) {
		if argument.hasPrefix("http") {
			self.init(string: argument)
		} else {
			self.init(fileURLWithPath: argument)
		}
	}
}
#else
extension URL: ExpressibleByArgument {

	public init?(argument: String) {
		if argument.hasPrefix("http") {
			self.init(string: argument)
		} else {
			self.init(fileURLWithPath: argument)
		}
	}
}
#endif
