//
// github.com/screensailor 2026
//

import Foundation

final class LSPTransport {
	private let input: FileHandle
	private let output: FileHandle
	private let encoder = JSONEncoder()
	private var buffer = Data()

	init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
		self.input = input
		self.output = output
	}

	func readMessage() -> Data? {
		while true {
			if let headerRange = headerRange(in: buffer) {
				let headerData = buffer[..<headerRange.lowerBound]
				let header = String(decoding: headerData, as: UTF8.self)
				guard let length = contentLength(in: header) else {
					return nil
				}
				let bodyStart = headerRange.upperBound
				let bodyEnd = bodyStart + length
				if buffer.count >= bodyEnd {
					let body = buffer[bodyStart..<bodyEnd]
					buffer.removeSubrange(..<bodyEnd)
					return Data(body)
				}
			}
			guard let chunk = try? input.read(upToCount: 1), chunk.isEmpty == false else {
				return nil
			}
			buffer.append(chunk)
		}
	}

	func respond<Result: Encodable>(id: LSPRequestID, result: Result) {
		write(LSPResponse(id: id, result: result))
	}

	func notify<Params: Encodable>(method: String, params: Params) {
		write(LSPNotification(method: method, params: params))
	}

	private func write<Value: Encodable>(_ value: Value) {
		guard let data = try? encoder.encode(value) else {
			return
		}
		let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
		output.write(header + data)
	}

	private func headerRange(in data: Data) -> Range<Data.Index>? {
		data.range(of: Data("\r\n\r\n".utf8))
			?? data.range(of: Data("\n\n".utf8))
	}

	private func contentLength(in header: String) -> Int? {
		header
			.replacingOccurrences(of: "\r", with: "")
			.components(separatedBy: "\n")
			.first(where: { $0.lowercased().hasPrefix("content-length:") })?
			.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
			.last
			.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
	}
}
