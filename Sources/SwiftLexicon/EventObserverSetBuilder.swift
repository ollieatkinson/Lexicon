//
// github.com/screensailor 2022
//

public typealias Bear = EventObserverSetBuilder
public typealias Mind = Set<EventObserver>

@resultBuilder public enum EventObserverSetBuilder {}

public extension EventObserverSetBuilder {

	typealias Element = EventObserver
	typealias Component = Set<Element>

	static func buildBlock(_ components: Element...) -> Component {
		components.reduce(into: [], +=)
	}

	static func buildBlock(_ first: Component, _ rest: Component...) -> Component {
		([first] + rest).reduce(into: [], +=)
	}

	static func buildExpression(_ expression: Element) -> Component {
		[expression]
	}

	static func buildExpression(_ expression: Component) -> Component {
		expression
	}

	static func buildOptional(_ component: Component?) -> Component {
		component ?? []
	}

	static func buildEither(first component: Component) -> Component {
		component
	}

	static func buildEither(second component: Component) -> Component {
		component
	}

	static func buildArray(_ components: [Component]) -> Component {
		components.reduce(into: [], +=)
	}

	static func buildLimitedAvailability(_ component: Component) -> Component {
		component
	}
}

public extension Set where Element == EventObserver {

	@inlinable static func += <A: Collection>(lhs: inout Self, rhs: A) where A.Element == EventObserver {
		lhs.formUnion(rhs)
	}

	@inlinable static func += (lhs: inout Self, rhs: EventObserver) {
		lhs.insert(rhs)
	}

	@inlinable mutating func `in`(_ mind: EventObserver) {
		insert(mind)
	}

	@inlinable mutating func `in`<A: Sequence>(_ mind: A) where A.Element == EventObserver {
		formUnion(mind)
	}
}
