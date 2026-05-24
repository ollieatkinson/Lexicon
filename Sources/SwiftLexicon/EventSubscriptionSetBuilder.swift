//
// github.com/screensailor 2022
//

public typealias Bear = EventSubscriptionSetBuilder
public typealias Mind = Set<EventSubscription>

@resultBuilder public enum EventSubscriptionSetBuilder {}

public extension EventSubscriptionSetBuilder {
	
	typealias Element = EventSubscription
	typealias Component = Set<Element>
	
	static func buildBlock(_ components: Element...) -> Component {
		components.reduce(into: [], +=)
	}
	
	static func buildBlock(_ first: Component, _ rest: Component...) -> Component {
		([first] + rest).reduce(into: [], +=)
	}
	
	// TODO: ...
}

public extension Set where Element == EventSubscription {
	
	@inlinable static func += <A: Collection>(lhs: inout Self, rhs: A) where A.Element == EventSubscription {
		lhs.formUnion(rhs)
	}
	
	@inlinable static func += (lhs: inout Self, rhs: EventSubscription) {
		lhs.insert(rhs)
	}
	
	@inlinable mutating func `in`(_ mind: EventSubscription) {
		insert(mind)
	}
	
	@inlinable mutating func `in`<A: Sequence>(_ mind: A) where A.Element == EventSubscription {
		formUnion(mind)
	}
}
