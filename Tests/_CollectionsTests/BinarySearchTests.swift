//
// github.com/screensailor 2026
//

import XCTest
import _Collections

final class BinarySearchTests: XCTestCase {

	func test_lower_bound_finds_first_insertable_index() {
		let values = [1, 2, 2, 4, 7]

		XCTAssertEqual(values.lowerBound(of: 0), 0)
		XCTAssertEqual(values.lowerBound(of: 2), 1)
		XCTAssertEqual(values.lowerBound(of: 3), 3)
		XCTAssertEqual(values.lowerBound(of: 8), 5)
	}

	func test_lower_bound_supports_extracted_keys() {
		let values = [
			(key: "alpha", value: 1),
			(key: "middle", value: 2),
			(key: "zeta", value: 3),
		]

		XCTAssertEqual(values.lowerBound(of: "aardvark", by: \.key), 0)
		XCTAssertEqual(values.lowerBound(of: "middle", by: \.key), 1)
		XCTAssertEqual(values.lowerBound(of: "omega", by: \.key), 2)
		XCTAssertEqual(values.lowerBound(of: "zz", by: \.key), 3)
	}
}
