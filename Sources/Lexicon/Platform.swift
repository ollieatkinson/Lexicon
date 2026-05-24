//
// github.com/screensailor 2026
//

import Foundation

#if !canImport(UniformTypeIdentifiers)
public struct UTType: Hashable, Sendable, CustomStringConvertible {
	public var preferredFilenameExtension: String?
	public var identifier: String

	public init(importedAs identifier: String) {
		self.identifier = identifier
		self.preferredFilenameExtension = identifier.split(separator: ".").last.map(String.init)
	}

	public init?(filenameExtension: String, conformingTo: UTType? = nil) {
		self.identifier = filenameExtension
		self.preferredFilenameExtension = filenameExtension
	}

	public var description: String {
		identifier
	}
}

public extension UTType {
	static let json = UTType(filenameExtension: "json")!
	static let swiftSource = UTType(filenameExtension: "swift")!
	static let sourceCode = UTType(filenameExtension: "txt")!
}
#endif
