//
// github.com/screensailor 2026
//

public extension RandomAccessCollection {

	func lowerBound<Value: Comparable>(
		of value: Value,
		by key: (Element) -> Value
	) -> Index {
		var start = startIndex
		var end = endIndex

		while start < end {
			let distance = self.distance(from: start, to: end)
			let middle = index(start, offsetBy: distance / 2)

			if key(self[middle]) < value {
				start = index(after: middle)
			} else {
				end = middle
			}
		}

		return start
	}
}

public extension RandomAccessCollection where Element: Comparable {

	func lowerBound(of element: Element) -> Index {
		lowerBound(of: element) { $0 }
	}
}
