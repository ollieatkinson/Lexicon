import PackagePlugin
import Foundation

@main
struct SwiftStandAloneGeneratorPlugin: BuildToolPlugin {

	func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
		do {
			let lexicon = try context.tool(named: "lexicon-generate")
			let outputDirectory = context.pluginWorkDirectoryURL
				.appendingPathComponent("GeneratedSources", isDirectory: true)
			let inputs = try lexiconInputs(in: target.directoryURL)
			guard inputs.count <= 1 else {
				throw PluginError.multipleStandaloneInputs(inputs.map(\.relativePath))
			}
			let outputs = try plannedOutputs(for: inputs, in: outputDirectory)

			for output in outputs {
				try FileManager.default.createDirectory(
					at: output.url.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
			}

			return outputs.map { output in
				.buildCommand(
					displayName: "Generate \(output.input.relativePath)",
					executable: lexicon.url,
					arguments: [
						output.input.url.path,
						"--output", output.url.deletingPathExtension().path,
						"--type", "swift-standalone"
					],
					inputFiles: [output.input.url],
					outputFiles: [output.url]
				)
			}
		} catch {
			Diagnostics.error(String(describing: error))
			throw error
		}
	}
}

private struct LexiconInput {
	let url: URL
	let relativePath: String
}

private struct PlannedOutput {
	let input: LexiconInput
	let url: URL
}

private enum PluginError: Error, CustomStringConvertible {
	case cannotEnumerate(URL)
	case inputOutsideTarget(URL)
	case outputCollision(String, String, String)
	case objectFilenameCollision(String, String, String)
	case multipleStandaloneInputs([String])

	var description: String {
		switch self {
			case .cannotEnumerate(let directory):
				"Unable to enumerate Lexicon inputs in '\(directory.path)'."
			case .inputOutsideTarget(let input):
				"Lexicon input '\(input.path)' is outside the target directory."
			case .outputCollision(let first, let second, let output):
				"Lexicon inputs '\(first)' and '\(second)' both map to generated output '\(output)'."
			case .objectFilenameCollision(let first, let second, let filename):
				"Lexicon inputs '\(first)' and '\(second)' both compile to object filename '\(filename).o'."
			case .multipleStandaloneInputs(let inputs):
				"""
				SwiftStandAloneGeneratorPlugin supports one .lexicon file per target because each output contains \
				the standalone runtime. Split inputs into targets or precompose them into one self-contained \
				.lexicon file before the plugin runs. \
				Found: \(inputs.joined(separator: ", ")).
				"""
		}
	}
}

private func lexiconInputs(in directory: URL) throws -> [LexiconInput] {
	let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
	var enumerationError: Error?
	guard let enumerator = FileManager.default.enumerator(
		at: directory,
		includingPropertiesForKeys: keys,
		options: [],
		errorHandler: { _, error in
			enumerationError = error
			return false
		}
	) else {
		throw PluginError.cannotEnumerate(directory)
	}

	var inputs: [LexiconInput] = []
	for case let input as URL in enumerator {
		guard input.pathExtension == "lexicon" else {
			continue
		}
		let values = try input.resourceValues(forKeys: Set(keys))
		guard values.isRegularFile == true, values.isSymbolicLink != true else {
			continue
		}
		inputs.append(.init(
			url: input,
			relativePath: try relativePath(of: input, in: directory)
		))
	}
	if let enumerationError {
		throw enumerationError
	}
	return inputs.sorted { $0.relativePath < $1.relativePath }
}

private func relativePath(of input: URL, in directory: URL) throws -> String {
	let directoryComponents = directory.standardizedFileURL.pathComponents
	let inputComponents = input.standardizedFileURL.pathComponents
	guard inputComponents.starts(with: directoryComponents) else {
		throw PluginError.inputOutsideTarget(input)
	}
	return inputComponents.dropFirst(directoryComponents.count).joined(separator: "/")
}

private func plannedOutputs(
	for inputs: [LexiconInput],
	in outputDirectory: URL
) throws -> [PlannedOutput] {
	var claimedOutputs: [String: String] = [:]
	var claimedObjectBasenames: [String: String] = [:]
	return try inputs.map { input in
		let relativePath = generatedRelativePath(for: input.relativePath)
		let collisionKey = normalizedCollisionKey(relativePath)
		let objectBasename = (relativePath as NSString).lastPathComponent
		let objectCollisionKey = normalizedCollisionKey(objectBasename)
		if let first = claimedObjectBasenames[objectCollisionKey] {
			throw PluginError.objectFilenameCollision(first, input.relativePath, objectBasename)
		}
		if let first = claimedOutputs[collisionKey] {
			throw PluginError.outputCollision(first, input.relativePath, relativePath)
		}
		claimedObjectBasenames[objectCollisionKey] = input.relativePath
		claimedOutputs[collisionKey] = input.relativePath
		return .init(
			input: input,
			url: outputDirectory.appendingPathComponent(relativePath)
		)
	}
}

private func generatedRelativePath(for inputRelativePath: String) -> String {
	let path = inputRelativePath as NSString
	let directory = path.deletingLastPathComponent
	let stem = (path.lastPathComponent as NSString).deletingPathExtension
	guard directory != "." else {
		return stem + ".swift"
	}

	// Swift compiles same-named files in different directories to the same object
	// filename, so the source basename must also encode its relative directory.
	let directoryPrefix = directory
		.split(separator: "/")
		.joined(separator: "__")
	let filename = "\(directoryPrefix)__\(stem).swift"
	return (directory as NSString).appendingPathComponent(filename)
}

private func normalizedCollisionKey(_ path: String) -> String {
	path
		.precomposedStringWithCanonicalMapping
		.lowercased()
}
