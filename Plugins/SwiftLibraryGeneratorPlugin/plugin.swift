import PackagePlugin
import Foundation

@main
struct SwiftLibraryGeneratorPlugin: BuildToolPlugin {

	func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
		let lexicon = try context.tool(named: "lexicon-generate")
		let output = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedSources", isDirectory: true)
		return FileManager.default.enumerator(at: target.directoryURL, includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension.hasSuffix("lexicon") }
			.map { input in
				let stem = input.deletingPathExtension().lastPathComponent
				return .buildCommand(
					displayName: "Generate \(input)",
					executable: lexicon.url,
					arguments: [
						input.path,
						"--output", output.appendingPathComponent(stem).path,
						"--type", "swift"
					],
					inputFiles: [input],
					outputFiles: [output.appendingPathComponent(stem + ".swift")]
				)
			} ?? []
	}
}
