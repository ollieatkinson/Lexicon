#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

pub trait I {
	fn id(&self) -> &str;
	fn localized(&self) -> &str;
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L {
	id: String,
}

impl L {
	pub fn new(id: impl Into<String>) -> Self {
		Self { id: id.into() }
	}
}

impl I for L {
	fn id(&self) -> &str {
		&self.id
	}

	fn localized(&self) -> &str {
		&self.id
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct Lexicon {
	pub test: L_test,
}

impl Lexicon {
	pub fn new() -> Self {
		Self {
			test: L_test::new("test"),
		}
	}
}

impl Default for Lexicon {
	fn default() -> Self {
		Self::new()
	}
}

pub fn l() -> Lexicon {
	Lexicon::new()
}

pub fn test() -> L_test {
	L_test::new("test")
}

macro_rules! __lexicon_l {
	(test) => {
		l().test
	};
	(test.one) => {
		l().test.one
	};
	(test.one.good) => {
		l().test.one.good()
	};
	(test.one.more) => {
		l().test.one.more
	};
	(test.one.more.time) => {
		l().test.one.more.time
	};
	(test.one.more.time.one) => {
		l().test.one.more.time.one()
	};
	(test.one.more.time.two) => {
		l().test.one.more.time.two()
	};
	(test.one.more.time.two.bad) => {
		l().test.one.more.time.two().bad()
	};
	(test.one.more.time.two.no) => {
		l().test.one.more.time.two().no()
	};
	(test.one.more.time.two.no.good) => {
		l().test.one.more.time.two().no().good
	};
	(test.one.more.time.two.timing) => {
		l().test.one.more.time.two().timing
	};
	(test.one.more.time.type) => {
		l().test.one.more.time.r#type()
	};
	(test.one.more.time.type.even) => {
		l().test.one.more.time.r#type().even
	};
	(test.one.more.time.type.even.bad) => {
		l().test.one.more.time.r#type().even.bad
	};
	(test.one.more.time.type.even.no) => {
		l().test.one.more.time.r#type().even.no
	};
	(test.one.more.time.type.even.no.good) => {
		l().test.one.more.time.r#type().even.no.good
	};
	(test.one.more.time.type.odd) => {
		l().test.one.more.time.r#type().odd
	};
	(test.one.more.time.type.odd.good) => {
		l().test.one.more.time.r#type().odd.good
	};
	(test.two) => {
		l().test.two
	};
	(test.two.bad) => {
		l().test.two.bad()
	};
	(test.two.no) => {
		l().test.two.no()
	};
	(test.two.no.good) => {
		l().test.two.no().good
	};
	(test.two.timing) => {
		l().test.two.timing
	};
	(test.type) => {
		l().test.r#type
	};
	(test.type.even) => {
		l().test.r#type.even
	};
	(test.type.even.bad) => {
		l().test.r#type.even.bad
	};
	(test.type.even.no) => {
		l().test.r#type.even.no
	};
	(test.type.even.no.good) => {
		l().test.r#type.even.no.good
	};
	(test.type.odd) => {
		l().test.r#type.odd
	};
	(test.type.odd.good) => {
		l().test.r#type.odd.good
	};
	($($path:tt)*) => {
		compile_error!(concat!("unknown Lexicon path: ", stringify!($($path)*)))
	};
}

pub(crate) use __lexicon_l as l;

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test {
	l: L,
	pub one: L_test_one,
	pub two: L_test_two,
	pub r#type: L_test_type,
}

impl L_test {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			one: L_test_one::new(format!("{}.one", id)),
			two: L_test_two::new(format!("{}.two", id)),
			r#type: L_test_type::new(format!("{}.type", id)),
		}
	}
}

impl I for L_test {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_one {
	l: L,
	pub more: L_test_one_more,
}

impl L_test_one {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			more: L_test_one_more::new(format!("{}.more", id)),
		}
	}

	pub fn good(&self) -> L_test_type_odd_good {
		L_test_type_odd_good::new(format!("{}.good", I::id(self)))
	}
}

impl I for L_test_one {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.one"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_one_more {
	l: L,
	pub time: L_test_one_more_time,
}

impl L_test_one_more {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			time: L_test_one_more_time::new(format!("{}.time", id)),
		}
	}
}

impl I for L_test_one_more {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.one.more"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_one_more_time {
	l: L,
}

impl L_test_one_more_time {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
		}
	}

	pub fn one(&self) -> L_test_one {
		L_test_one::new(format!("{}.one", I::id(self)))
	}

	pub fn two(&self) -> L_test_two {
		L_test_two::new(format!("{}.two", I::id(self)))
	}

	pub fn r#type(&self) -> L_test_type {
		L_test_type::new(format!("{}.type", I::id(self)))
	}
}

impl I for L_test_one_more_time {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.one.more.time"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_two {
	l: L,
	pub timing: L_test_two_timing,
}

impl L_test_two {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			timing: L_test_two_timing::new(format!("{}.timing", id)),
		}
	}

	pub fn bad(&self) -> L_test_type_even_bad {
		L_test_type_even_no_good::new(format!("{}.no.good", I::id(self)))
	}

	pub fn no(&self) -> L_test_type_even_no {
		L_test_type_even_no::new(format!("{}.no", I::id(self)))
	}
}

impl I for L_test_two {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.two"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_two_timing {
	l: L,
}

impl L_test_two_timing {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
		}
	}
}

impl I for L_test_two_timing {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.two.timing"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type {
	l: L,
	pub even: L_test_type_even,
	pub odd: L_test_type_odd,
}

impl L_test_type {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			even: L_test_type_even::new(format!("{}.even", id)),
			odd: L_test_type_odd::new(format!("{}.odd", id)),
		}
	}
}

impl I for L_test_type {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type_even {
	l: L,
	pub no: L_test_type_even_no,
	pub bad: L_test_type_even_bad,
}

impl L_test_type_even {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			no: L_test_type_even_no::new(format!("{}.no", id)),
			bad: L_test_type_even_no_good::new(format!("{}.no.good", id)),
		}
	}
}

impl I for L_test_type_even {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type.even"
	}
}

pub type L_test_type_even_bad = L_test_type_even_no_good;

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type_even_no {
	l: L,
	pub good: L_test_type_even_no_good,
}

impl L_test_type_even_no {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			good: L_test_type_even_no_good::new(format!("{}.good", id)),
		}
	}
}

impl I for L_test_type_even_no {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type.even.no"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type_even_no_good {
	l: L,
}

impl L_test_type_even_no_good {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
		}
	}
}

impl I for L_test_type_even_no_good {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type.even.no.good"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type_odd {
	l: L,
	pub good: L_test_type_odd_good,
}

impl L_test_type_odd {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
			good: L_test_type_odd_good::new(format!("{}.good", id)),
		}
	}
}

impl I for L_test_type_odd {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type.odd"
	}
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct L_test_type_odd_good {
	l: L,
}

impl L_test_type_odd_good {
	pub fn new(id: impl Into<String>) -> Self {
		let id = id.into();
		Self {
			l: L::new(id.clone()),
		}
	}
}

impl I for L_test_type_odd_good {
	fn id(&self) -> &str {
		I::id(&self.l)
	}

	fn localized(&self) -> &str {
		"test.type.odd.good"
	}
}
