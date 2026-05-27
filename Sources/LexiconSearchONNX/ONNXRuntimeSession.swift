#if ONNXSearch
import Foundation
import OnnxRuntimeBindings

public final class ONNXRuntimeSession: @unchecked Sendable {
	private var env: ORTEnv
	private var session: ORTSession

	public var inputNames: [String]
	public var outputNames: [String]
	public var runtimeVersion: String {
		ORTVersion() ?? "unknown"
	}

	public init(model: URL) throws {
		self.env = try ORTEnv(loggingLevel: .warning)
		let options = try ORTSessionOptions()
		try options.setGraphOptimizationLevel(.basic)
		self.session = try ORTSession(
			env: env,
			modelPath: model.path,
			sessionOptions: options
		)
		self.inputNames = try session.inputNames()
		self.outputNames = try session.outputNames()
	}

	public func run(batch: ONNXTokenBatch) throws -> ONNXFloatTensor {
		guard
			let inputIDsName = preferredName("input_ids", in: inputNames),
			let attentionMaskName = preferredName("attention_mask", in: inputNames)
		else {
			throw ONNXRuntimeError("Model inputs \(inputNames) do not include input_ids and attention_mask.")
		}
		let tokenTypeIDsName = preferredName("token_type_ids", in: inputNames)
		let outputName = preferredOutputName()
		var inputs = [
			inputIDsName: try int64Tensor(batch.inputIDs),
			attentionMaskName: try int64Tensor(batch.attentionMask),
		]
		if let tokenTypeIDsName {
			inputs[tokenTypeIDsName] = try int64Tensor(batch.tokenTypeIDs)
		}
		let outputs = try session.run(
			withInputs: inputs,
			outputNames: [outputName],
			runOptions: nil
		)
		guard let output = outputs[outputName] else {
			throw ONNXRuntimeError("ONNX Runtime did not return output '\(outputName)'.")
		}
		return try floatTensor(from: output)
	}

	private func int64Tensor(_ rows: [[Int64]]) throws -> ORTValue {
		let values = rows.flatMap { $0 }
		let data = values.withUnsafeBufferPointer { buffer in
			NSMutableData(
				bytes: buffer.baseAddress,
				length: buffer.count * MemoryLayout<Int64>.stride
			)
		}
		let shape = [
			NSNumber(value: rows.count),
			NSNumber(value: rows.first?.count ?? 0),
		]
		return try ORTValue(
			tensorData: data,
			elementType: .int64,
			shape: shape
		)
	}

	private func floatTensor(from output: ORTValue) throws -> ONNXFloatTensor {
		let info = try output.tensorTypeAndShapeInfo()
		guard info.elementType == .float else {
			throw ONNXRuntimeError("Expected float output tensor, found \(info.elementType).")
		}
		let data = try output.tensorData()
		let count = data.length / MemoryLayout<Float>.stride
		let pointer = data.bytes.assumingMemoryBound(to: Float.self)
		let values = Array(UnsafeBufferPointer(start: pointer, count: count))
		let shape = info.shape.map(\.intValue)
		return .init(values: values, shape: shape)
	}

	private func preferredName(_ name: String, in names: [String]) -> String? {
		names.first { $0 == name }
	}

	private func preferredOutputName() -> String {
		for name in ["sentence_embedding", "last_hidden_state", "token_embeddings"] {
			if outputNames.contains(name) {
				return name
			}
		}
		return outputNames.first ?? "last_hidden_state"
	}
}
#endif
