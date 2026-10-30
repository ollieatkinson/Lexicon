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
}
