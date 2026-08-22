import Foundation

public enum ONNXPooling: String, Codable, Hashable, Sendable {
	case mean
	case cls
	case lastToken

	public func vectors(
		from tensor: ONNXFloatTensor,
		attentionMask: [[Int64]],
		normalized: Bool = true
	) throws -> [[Double]] {
		switch tensor.shape.count {
			case 2:
				return try pooledVectors(fromRank2: tensor, normalized: normalized)
			case 3:
				return try pooledVectors(fromRank3: tensor, attentionMask: attentionMask, normalized: normalized)
			default:
				throw ONNXRuntimeError("Unsupported embedding output shape: \(tensor.shape)")
		}
	}

	private func pooledVectors(fromRank2 tensor: ONNXFloatTensor, normalized: Bool) throws -> [[Double]] {
		let batch = tensor.shape[0]
		let dimensions = tensor.shape[1]
		guard tensor.values.count == batch * dimensions else {
			throw ONNXRuntimeError("Output tensor shape \(tensor.shape) does not match \(tensor.values.count) values.")
		}
		return (0..<batch).map { row in
			let start = row * dimensions
			let end = start + dimensions
			let vector = tensor.values[start..<end].map(Double.init)
			return normalized ? l2Normalize(vector) : vector
		}
	}

	private func pooledVectors(
		fromRank3 tensor: ONNXFloatTensor,
		attentionMask: [[Int64]],
		normalized: Bool
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
			let vector: [Double]
			switch self {
				case .mean:
					vector = meanVector(
						tensor: tensor,
						batchIndex: batchIndex,
						tokens: tokens,
						dimensions: dimensions,
						attentionMask: attentionMask[batchIndex]
					)
				case .cls:
					vector = tokenVector(tensor: tensor, batchIndex: batchIndex, tokenIndex: 0, dimensions: dimensions)
				case .lastToken:
					let lastIndex = attentionMask[batchIndex].lastIndex { $0 != 0 } ?? 0
					vector = tokenVector(tensor: tensor, batchIndex: batchIndex, tokenIndex: lastIndex, dimensions: dimensions)
			}
			return normalized ? l2Normalize(vector) : vector
		}
	}

	private func meanVector(
		tensor: ONNXFloatTensor,
		batchIndex: Int,
		tokens: Int,
		dimensions: Int,
		attentionMask: [Int64]
	) -> [Double] {
		var vector = Array(repeating: 0.0, count: dimensions)
		var tokenCount = 0.0
		for tokenIndex in 0..<tokens where attentionMask[tokenIndex] != 0 {
			tokenCount += 1
			let tokenOffset = (batchIndex * tokens * dimensions) + (tokenIndex * dimensions)
			for dimension in 0..<dimensions {
				vector[dimension] += Double(tensor.values[tokenOffset + dimension])
			}
		}
		guard tokenCount > 0 else {
			return vector
		}
		return vector.map { $0 / tokenCount }
	}

	private func tokenVector(
		tensor: ONNXFloatTensor,
		batchIndex: Int,
		tokenIndex: Int,
		dimensions: Int
	) -> [Double] {
		let tokenOffset = (batchIndex * tensor.shape[1] * dimensions) + (tokenIndex * dimensions)
		return tensor.values[tokenOffset..<(tokenOffset + dimensions)].map(Double.init)
	}
}

public func l2Normalize(_ vector: [Double]) -> [Double] {
	let norm = sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
	guard norm > 0 else {
		return vector
	}
	return vector.map { $0 / norm }
}
