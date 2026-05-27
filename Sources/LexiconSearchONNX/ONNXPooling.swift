import Foundation

public enum ONNXPooling: Sendable {
	case mean

	public func vectors(from tensor: ONNXFloatTensor, attentionMask: [[Int64]]) throws -> [[Double]] {
		switch tensor.shape.count {
			case 2:
				return try pooledVectors(fromRank2: tensor)
			case 3:
				return try meanPooledVectors(fromRank3: tensor, attentionMask: attentionMask)
			default:
				throw ONNXRuntimeError("Unsupported embedding output shape: \(tensor.shape)")
		}
	}

	private func pooledVectors(fromRank2 tensor: ONNXFloatTensor) throws -> [[Double]] {
		let batch = tensor.shape[0]
		let dimensions = tensor.shape[1]
		guard tensor.values.count == batch * dimensions else {
			throw ONNXRuntimeError("Output tensor shape \(tensor.shape) does not match \(tensor.values.count) values.")
		}
		return (0..<batch).map { row in
			let start = row * dimensions
			let end = start + dimensions
			return l2Normalize(tensor.values[start..<end].map(Double.init))
		}
	}

	private func meanPooledVectors(
		fromRank3 tensor: ONNXFloatTensor,
		attentionMask: [[Int64]]
	) throws -> [[Double]] {
		let batch = tensor.shape[0]
		let tokens = tensor.shape[1]
		let dimensions = tensor.shape[2]
		guard tensor.values.count == batch * tokens * dimensions else {
			throw ONNXRuntimeError("Output tensor shape \(tensor.shape) does not match \(tensor.values.count) values.")
		}
		guard attentionMask.count == batch else {
			throw ONNXRuntimeError("Attention mask batch size does not match output batch size.")
		}

		return try (0..<batch).map { batchIndex in
			guard attentionMask[batchIndex].count == tokens else {
				throw ONNXRuntimeError("Attention mask token count does not match output token count.")
			}
			var vector = Array(repeating: 0.0, count: dimensions)
			var tokenCount = 0.0
			for tokenIndex in 0..<tokens where attentionMask[batchIndex][tokenIndex] != 0 {
				tokenCount += 1
				let tokenOffset = (batchIndex * tokens * dimensions) + (tokenIndex * dimensions)
				for dimension in 0..<dimensions {
					vector[dimension] += Double(tensor.values[tokenOffset + dimension])
				}
			}
			guard tokenCount > 0 else {
				return vector
			}
			return l2Normalize(vector.map { $0 / tokenCount })
		}
	}
}

public func l2Normalize(_ vector: [Double]) -> [Double] {
	let norm = sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
	guard norm > 0 else {
		return vector
	}
	return vector.map { $0 / norm }
}
