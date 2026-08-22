import Foundation
import LexiconSearchONNX
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct ONNXSearchArtifacts {
	static func main() async throws {
		let arguments = try Arguments(CommandLine.arguments.dropFirst())
		if arguments.skipModel == false {
			try await installModel(arguments.model, output: arguments.output, force: arguments.force)
		}
		for runtime in arguments.runtimes {
			try await installRuntime(runtime, output: arguments.runtimeOutput, version: arguments.runtimeVersion, force: arguments.force)
		}
	}

	private static func installModel(_ model: ONNXSearchModel, output: URL, force: Bool) async throws {
		guard let artifact = model.artifact else {
			throw ONNXArtifactsError("Model \(model.id) does not declare a downloadable artifact.")
		}
		let modelDirectory = model.localDirectory(in: output)
		try FileManager.default.createDirectory(
			at: modelDirectory,
			withIntermediateDirectories: true
		)
		let revisionURL = modelDirectory.appendingPathComponent("REVISION")
		let installedRevision = try? String(contentsOf: revisionURL, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let force = force || installedRevision != model.revision
		try await download(
			path: artifact.modelPath,
			to: model.localModelURL(in: output),
			model: model,
			force: force
		)
		try await download(
			path: artifact.vocabularyPath,
			to: model.localVocabularyURL(in: output),
			model: model,
			force: force
		)
		try model.revision.write(
			to: revisionURL,
			atomically: true,
			encoding: .utf8
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		try encoder.encode(model).write(to: model.localManifestURL(in: output))
		print("ONNX search artifacts: \(modelDirectory.path)")
	}

	private static func download(
		path: String,
		to output: URL,
		model: ONNXSearchModel,
		force: Bool
	) async throws {
		if !force, FileManager.default.fileExists(atPath: output.path) {
			return
		}
		let url = try model.artifactURL(path: path)
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

	private static func installRuntime(
		_ runtime: ONNXRuntimeArtifact,
		output: URL,
		version: String,
		force: Bool
	) async throws {
		let root = output.appendingPathComponent("current", isDirectory: true)
		let downloads = output.appendingPathComponent("downloads", isDirectory: true)
		let extraction = output
			.appendingPathComponent("extract", isDirectory: true)
			.appendingPathComponent(runtime.id, isDirectory: true)
		try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)

		let archive = downloads.appendingPathComponent(runtime.archiveName(version: version))
		if force || FileManager.default.fileExists(atPath: archive.path) == false {
			let url = try runtime.url(version: version)
			print("Downloading \(url.lastPathComponent)")
			let (temporary, response) = try await URLSession.shared.download(from: url)
			if let response = response as? HTTPURLResponse,
			   !(200..<300).contains(response.statusCode)
			{
				throw ONNXArtifactsError("Download failed with HTTP \(response.statusCode): \(url.absoluteString)")
			}
			if FileManager.default.fileExists(atPath: archive.path) {
				try FileManager.default.removeItem(at: archive)
			}
			try FileManager.default.moveItem(at: temporary, to: archive)
		}

		if force, FileManager.default.fileExists(atPath: extraction.path) {
			try FileManager.default.removeItem(at: extraction)
			try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
		}
		try extract(archive, to: extraction)
		try runtime.install(from: extraction, to: root, version: version)
		print("ONNX Runtime \(runtime.id): \(root.path)")
	}

	private static func extract(_ archive: URL, to output: URL) throws {
		let tool = archive.pathExtension == "tgz" ? "tar" : "unzip"
		let arguments = archive.pathExtension == "tgz"
			? ["-xzf", archive.path, "-C", output.path]
			: ["-oq", archive.path, "-d", output.path]
		let process = try Process.run(
			URL(fileURLWithPath: "/usr/bin/env"),
			arguments: [tool] + arguments
		)
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			throw ONNXArtifactsError("Failed to extract \(archive.lastPathComponent) with \(tool).")
		}
	}
}

private struct Arguments {
	var output: URL
	var runtimeOutput: URL
	var force: Bool
	var skipModel: Bool
	var model: ONNXSearchModel
	var runtimes: [ONNXRuntimeArtifact]
	var runtimeVersion: String

	init(_ rawArguments: ArraySlice<String>) throws {
		var values = Array(rawArguments)
		output = URL(fileURLWithPath: ".build/onnx-search")
		runtimeOutput = URL(fileURLWithPath: ".build/onnx-runtime")
		force = false
		skipModel = false
		runtimes = []
		runtimeVersion = "1.24.2"
		var preset: String?
		var manifest: URL?
		var id: String?
		var repository: String?
		var revision: String?
		var modelPath: String?
		var vocabularyPath: String?
		var dimensions: Int?
		var maxLength: Int?
		while !values.isEmpty {
			let flag = values.removeFirst()
			switch flag {
				case "--output":
					output = try URL(argument: &values, flag: flag)
				case "--runtime-output":
					runtimeOutput = try URL(argument: &values, flag: flag)
				case "--force":
					force = true
				case "--skip-model":
					skipModel = true
				case "--preset":
					preset = try String(argument: &values, flag: flag)
				case "--runtime":
					let value = try String(argument: &values, flag: flag)
					if value == "all" {
						runtimes = ONNXRuntimeArtifact.allCases
					} else {
						runtimes.append(try ONNXRuntimeArtifact(argument: value))
					}
				case "--runtime-version":
					runtimeVersion = try String(argument: &values, flag: flag)
				case "--manifest":
					manifest = try URL(argument: &values, flag: flag)
				case "--id":
					id = try String(argument: &values, flag: flag)
				case "--repository":
					repository = try String(argument: &values, flag: flag)
				case "--revision":
					revision = try String(argument: &values, flag: flag)
				case "--model-path":
					modelPath = try String(argument: &values, flag: flag)
				case "--vocabulary-path":
					vocabularyPath = try String(argument: &values, flag: flag)
				case "--dimensions":
					dimensions = try Int(argument: &values, flag: flag)
				case "--max-length":
					maxLength = try Int(argument: &values, flag: flag)
				default:
					throw ONNXArtifactsError("Unknown argument: \(flag)")
			}
		}
		model = try Self.model(
			preset: preset,
			manifest: manifest,
			id: id,
			repository: repository,
			revision: revision,
			modelPath: modelPath,
			vocabularyPath: vocabularyPath,
			dimensions: dimensions,
			maxLength: maxLength
		)
	}

	private static func model(
		preset: String?,
		manifest: URL?,
		id: String?,
		repository: String?,
		revision: String?,
		modelPath: String?,
		vocabularyPath: String?,
		dimensions: Int?,
		maxLength: Int?
	) throws -> ONNXSearchModel {
		var model: ONNXSearchModel
		if let manifest {
			model = try JSONDecoder().decode(ONNXSearchModel.self, from: Data(contentsOf: manifest))
		} else {
			let preset = preset ?? ONNXSearchModel.default.id
			guard let selected = ONNXSearchModel.preset(named: preset) else {
				throw ONNXArtifactsError("Unknown ONNX search model preset: \(preset)")
			}
			model = selected
		}
		if let id {
			model.id = id
		}
		if let revision {
			model.revision = revision
		}
		if let dimensions {
			model.dimensions = dimensions
		}
		if let maxLength {
			model.maxLength = maxLength
		}
		if repository != nil || modelPath != nil || vocabularyPath != nil {
			guard
				let repository = repository ?? model.artifact?.repository,
				let modelPath = modelPath ?? model.artifact?.modelPath,
				let vocabularyPath = vocabularyPath ?? model.artifact?.vocabularyPath
			else {
				throw ONNXArtifactsError("Custom ONNX artifact downloads require repository, model path, and vocabulary path.")
			}
			model.artifact = .init(
				repository: repository,
				modelPath: modelPath,
				vocabularyPath: vocabularyPath
			)
		}
		return model
	}
}

private enum ONNXRuntimeArtifact: String, CaseIterable {
	case linuxX64 = "linux-x64"
	case linuxAarch64 = "linux-aarch64"
	case android = "android"

	var id: String {
		rawValue
	}

	init(argument: String) throws {
		guard let artifact = Self(rawValue: argument) else {
			throw ONNXArtifactsError("Unknown ONNX runtime '\(argument)'. Expected linux-x64, linux-aarch64, android, or all.")
		}
		self = artifact
	}

	func archiveName(version: String) -> String {
		switch self {
			case .linuxX64:
				"onnxruntime-linux-x64-\(version).tgz"
			case .linuxAarch64:
				"onnxruntime-linux-aarch64-\(version).tgz"
			case .android:
				"onnxruntime-android-\(version).aar"
		}
	}

	func url(version: String) throws -> URL {
		let string: String
		switch self {
			case .linuxX64, .linuxAarch64:
				string = "https://github.com/microsoft/onnxruntime/releases/download/v\(version)/\(archiveName(version: version))"
			case .android:
				string = "https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/\(version)/\(archiveName(version: version))"
		}
		guard let url = URL(string: string) else {
			throw ONNXArtifactsError("Invalid ONNX Runtime URL: \(string)")
		}
		return url
	}

	func install(from extraction: URL, to root: URL, version: String) throws {
		switch self {
			case .linuxX64:
				try installReleaseArchive(
					from: extraction.appendingPathComponent("onnxruntime-linux-x64-\(version)", isDirectory: true),
					to: root,
					libDirectoryName: "linux-x64"
				)
			case .linuxAarch64:
				try installReleaseArchive(
					from: extraction.appendingPathComponent("onnxruntime-linux-aarch64-\(version)", isDirectory: true),
					to: root,
					libDirectoryName: "linux-aarch64"
				)
			case .android:
				try copyDirectoryContents(
					from: extraction.appendingPathComponent("headers", isDirectory: true),
					to: root.appendingPathComponent("include", isDirectory: true)
				)
				for abi in ["arm64-v8a", "x86_64"] {
					try copyDirectoryContents(
						from: extraction
							.appendingPathComponent("jni", isDirectory: true)
							.appendingPathComponent(abi, isDirectory: true),
						to: root
							.appendingPathComponent("lib", isDirectory: true)
							.appendingPathComponent("android-\(abi)", isDirectory: true)
					)
				}
		}
	}

	private func installReleaseArchive(from archiveRoot: URL, to root: URL, libDirectoryName: String) throws {
		try copyDirectoryContents(
			from: archiveRoot.appendingPathComponent("include", isDirectory: true),
			to: root.appendingPathComponent("include", isDirectory: true)
		)
		try copyDirectoryContents(
			from: archiveRoot.appendingPathComponent("lib", isDirectory: true),
			to: root
				.appendingPathComponent("lib", isDirectory: true)
				.appendingPathComponent(libDirectoryName, isDirectory: true)
		)
	}
}

private struct ONNXArtifactsError: Error, CustomStringConvertible {
	var description: String

	init(_ description: String) {
		self.description = description
	}
}

private func copyDirectoryContents(from source: URL, to destination: URL) throws {
	guard FileManager.default.fileExists(atPath: source.path) else {
		throw ONNXArtifactsError("Missing ONNX Runtime artifact directory: \(source.path)")
	}
	if FileManager.default.fileExists(atPath: destination.path) {
		try FileManager.default.removeItem(at: destination)
	}
	try FileManager.default.createDirectory(
		at: destination,
		withIntermediateDirectories: true
	)
	for item in try FileManager.default.contentsOfDirectory(
		at: source,
		includingPropertiesForKeys: nil
	) {
		try FileManager.default.copyItem(
			at: item,
			to: destination.appendingPathComponent(item.lastPathComponent)
		)
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

private extension Int {
	init(argument values: inout [String], flag: String) throws {
		let value = try String(argument: &values, flag: flag)
		guard let integer = Int(value) else {
			throw ONNXArtifactsError("Invalid integer for \(flag): \(value)")
		}
		self = integer
	}
}
