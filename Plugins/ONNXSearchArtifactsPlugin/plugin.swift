import Foundation
import PackagePlugin

@main
struct ONNXSearchArtifactsPlugin: CommandPlugin {

	func performCommand(context: PluginContext, arguments: [String]) async throws {
		let tool = try context.tool(named: "onnx-search-artifacts")
		var arguments = arguments
		if arguments.first == "--" {
			arguments.removeFirst()
		}
		let output = context.package.directoryURL
			.appendingPathComponent(".build", isDirectory: true)
			.appendingPathComponent("onnx-search", isDirectory: true)
		let runtimeOutput = context.package.directoryURL
			.appendingPathComponent(".build", isDirectory: true)
			.appendingPathComponent("onnx-runtime", isDirectory: true)
		let process = try Process.run(
			tool.url,
			arguments: [
				"--output", output.path,
				"--runtime-output", runtimeOutput.path,
			] + arguments
		)
		process.waitUntilExit()
		if process.terminationStatus != 0 {
			throw ONNXSearchArtifactsPluginError(status: process.terminationStatus)
		}
	}
}

private struct ONNXSearchArtifactsPluginError: Error, CustomStringConvertible {
	var status: Int32

	var description: String {
		"ONNX search artifact setup failed with exit status \(status)."
	}
}
