#if ONNXSearch && !canImport(OnnxRuntimeBindings) && canImport(CLexiconONNXRuntime)
import CLexiconONNXRuntime
import Foundation

public final class ONNXRuntimeSession: @unchecked Sendable {
	private var session: LexiconONNXRuntimeSessionRef?

	public var inputNames: [String] {
		[]
	}

	public var outputNames: [String] {
		[]
	}

	public var runtimeVersion: String {
		guard let version = LexiconONNXRuntimeVersion() else {
			return "unknown"
		}
		return String(cString: version)
	}

	public init(model: URL) throws {
		var created: LexiconONNXRuntimeSessionRef?
		var error: UnsafeMutablePointer<CChar>?
		let ok = model.path.withCString { path in
			LexiconONNXRuntimeCreateSession(path, &created, &error)
		}
		try Self.check(ok, error: error)
		self.session = created
	}

	deinit {
		if let session {
			LexiconONNXRuntimeReleaseSession(session)
		}
	}

	public func run(batch: ONNXTokenBatch, model: ONNXSearchModel) throws -> ONNXFloatTensor {
		guard let session else {
			throw ONNXRuntimeError("ONNX Runtime session has not been created.")
		}
		var inputIDs = batch.inputIDs.flatMap { $0 }
		var attentionMask = batch.attentionMask.flatMap { $0 }
		var tokenTypeIDs = batch.tokenTypeIDs.flatMap { $0 }
		let shape = [Int64(batch.inputIDs.count), Int64(batch.inputIDs.first?.count ?? 0)]
		var inputNames = [
			model.inputIDsName,
			model.attentionMaskName,
		]
		if let tokenTypeIDsName = model.tokenTypeIDsName {
			inputNames.append(tokenTypeIDsName)
		}

		return try inputIDs.withUnsafeMutableBufferPointer { inputIDBuffer in
			try attentionMask.withUnsafeMutableBufferPointer { attentionMaskBuffer in
				try tokenTypeIDs.withUnsafeMutableBufferPointer { tokenTypeIDBuffer in
					var inputData = [
						UnsafePointer(inputIDBuffer.baseAddress),
						UnsafePointer(attentionMaskBuffer.baseAddress),
					]
					if model.tokenTypeIDsName != nil {
						inputData.append(UnsafePointer(tokenTypeIDBuffer.baseAddress))
					}
					return try withCStringPointers(inputNames) { inputNamePointers in
						try model.outputName.withCString { outputName in
							try inputData.withUnsafeBufferPointer { inputDataPointers in
								try shape.withUnsafeBufferPointer { shapePointer in
									var outputValues: UnsafeMutablePointer<Float>?
									var outputValueCount = 0
									var outputShape: UnsafeMutablePointer<Int64>?
									var outputShapeCount = 0
									var error: UnsafeMutablePointer<CChar>?
									let ok = LexiconONNXRuntimeRun(
										session,
										inputNamePointers.baseAddress,
										inputDataPointers.baseAddress,
										inputData.count,
										shapePointer.baseAddress,
										shape.count,
										outputName,
										&outputValues,
										&outputValueCount,
										&outputShape,
										&outputShapeCount,
										&error
									)
									try Self.check(ok, error: error)
									defer {
										LexiconONNXRuntimeReleaseTensor(outputValues, outputShape)
									}
									guard let outputValues, let outputShape else {
										throw ONNXRuntimeError("ONNX Runtime returned empty output.")
									}
									return ONNXFloatTensor(
										values: Array(UnsafeBufferPointer(
											start: outputValues,
											count: outputValueCount
										)),
										shape: Array(UnsafeBufferPointer(
											start: outputShape,
											count: outputShapeCount
										)).map(Int.init)
									)
								}
							}
						}
					}
				}
			}
		}
	}

	private static func check(_ ok: Int32, error: UnsafeMutablePointer<CChar>?) throws {
		guard ok == 0 else {
			return
		}
		let message = error.map { String(cString: $0) } ?? "unknown ONNX Runtime error"
		if let error {
			LexiconONNXRuntimeReleaseError(error)
		}
		throw ONNXRuntimeError(message)
	}

	private func withCStringPointers<Result>(
		_ strings: [String],
		_ body: (UnsafeBufferPointer<UnsafePointer<CChar>?>) throws -> Result
	) throws -> Result {
		var pointers: [UnsafePointer<CChar>?] = []
		func append(_ index: Int) throws -> Result {
			guard index < strings.count else {
				return try pointers.withUnsafeBufferPointer(body)
			}
			return try strings[index].withCString { pointer in
				pointers.append(pointer)
				defer {
					pointers.removeLast()
				}
				return try append(index + 1)
			}
		}
		return try append(0)
	}
}
#endif
