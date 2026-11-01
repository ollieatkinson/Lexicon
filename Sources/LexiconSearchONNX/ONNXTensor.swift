import Foundation

public struct ONNXFloatTensor: Sendable {
	public var values: [Float]
	public var shape: [Int]

	public init(values: [Float], shape: [Int]) {
		self.values = values
		self.shape = shape
	}
}

public struct ONNXTokenBatch: Sendable {
	public var inputIDs: [[Int64]]
	public var attentionMask: [[Int64]]
	public var tokenTypeIDs: [[Int64]]

	public init(inputIDs: [[Int64]], attentionMask: [[Int64]], tokenTypeIDs: [[Int64]]) {
		self.inputIDs = inputIDs
		self.attentionMask = attentionMask
		self.tokenTypeIDs = tokenTypeIDs
	}

	func validate(requiresTokenTypeIDs: Bool) throws {
		guard let width = inputIDs.first?.count, width > 0,
			inputIDs.allSatisfy({ $0.count == width }),
			attentionMask.count == inputIDs.count,
			attentionMask.allSatisfy({ $0.count == width }),
			!requiresTokenTypeIDs || (tokenTypeIDs.count == inputIDs.count
				&& tokenTypeIDs.allSatisfy({ $0.count == width })) else {
			throw ONNXRuntimeError("ONNX input tensors must have the same non-empty rectangular shape.")
		}
	}
}
