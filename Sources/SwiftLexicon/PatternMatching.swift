/// Matches a generated lemma or bracketed context against its exact identifier.
///
/// This allows a string switch to use `case namespace.command:` directly.
@inlinable
public func ~= (pattern: any I, value: String) -> Bool {
    pattern.__ == value
}
