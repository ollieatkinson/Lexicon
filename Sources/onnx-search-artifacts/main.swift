import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct ONNXSearchArtifacts {
	private static let modelRevision = "c9745ed1d9f207416be6d2e6f8de32d1f16199bf"
	private static let repository = "sentence-transformers/all-MiniLM-L6-v2"

	static func main() async throws {
		let arguments = try Arguments(CommandLine.arguments.dropFirst())
		let modelDirectory = arguments.output
			.appendingPathComponent("all-MiniLM-L6-v2", isDirectory: true)
		try FileManager.default.createDirectory(
			at: modelDirectory,
			withIntermediateDirectories: true
		)
		try await download(
			path: "onnx/model.onnx",
			to: modelDirectory.appendingPathComponent("model.onnx"),
			force: arguments.force
		)
		try await download(
			path: "vocab.txt",
			to: modelDirectory.appendingPathComponent("vocab.txt"),
			force: arguments.force
		)
		try modelRevision.write(
			to: modelDirectory.appendingPathComponent("REVISION"),
			atomically: true,
			encoding: .utf8
		)
		print("ONNX search artifacts: \(modelDirectory.path)")
	}

	private static func download(path: String, to output: URL, force: Bool) async throws {
		if !force, FileManager.default.fileExists(atPath: output.path) {
			return
		}
		let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(modelRevision)/\(path)")!
		print("Downloading \(path)")
		let (temporary, response) = try await URLSession.shared.download(from: url)
		if let response = response as? HTTPURLResponse,
		   !(200..<300).contains(response.statusCode)
		{
			throw ONNXArtifactsError("Download failed with HTTP \(response.statusCode): \(url.absoluteString)")
		}
		if FileManager.default.fileExists(atPath: output.path) {
			try FileManager.default.removeItem(at: output)
		}
		try FileManager.default.moveItem(at: temporary, to: output)
	}
}

private struct Arguments {
	var output: URL
	var force: Bool

	init(_ rawArguments: ArraySlice<String>) throws {
		var values = Array(rawArguments)
		output = URL(fileURLWithPath: ".build/onnx-search")
		force = false
		while !values.isEmpty {
			let flag = values.removeFirst()
			switch flag {
				case "--output":
					output = try URL(argument: &values, flag: flag)
				case "--force":
					force = true
				default:
					throw ONNXArtifactsError("Unknown argument: \(flag)")
			}
		}
	}
}

private struct ONNXArtifactsError: Error, CustomStringConvertible {
	var description: String

	init(_ description: String) {
		self.description = description
	}
}

private extension URL {
	init(argument values: inout [String], flag: String) throws {
		let value = try String(argument: &values, flag: flag)
		self.init(fileURLWithPath: value)
	}
}

private extension String {
	init(argument values: inout [String], flag: String) throws {
		guard !values.isEmpty else {
			throw ONNXArtifactsError("Missing value for \(flag).")
		}
		self = values.removeFirst()
	}
}
