fn main() {
	let valid = l!(test.type.even.bad);
	let invalid = l!(test.type.even.bed);
	let complete_here = l!(test.type.even.);

	_ = (valid, invalid, complete_here);
}
