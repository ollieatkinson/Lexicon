export interface I { }

// L
export class L implements I {
	protected id: string;
	constructor(id: string) {
		this.id = id;
	}
	get ['__']() {
		return this.id;
	}
}

// MARK: generated types
export class L_test extends L implements I_test {
  one = new L_test_one(`${this.__}.one`);
  two = new L_test_two(`${this.__}.two`);
  type = new L_test_type(`${this.__}.type`);
}
export interface I_test extends I {
  one: I_test_one;
  two: I_test_two;
  type: I_test_type;
}
export class L_test_one extends L implements I_test_one {
  get good() { return new L_test_type_odd_good(`${this.__}.good`); }
  more = new L_test_one_more(`${this.__}.more`);
}
export interface I_test_one extends I_test_type_odd {
  more: I_test_one_more;
}
export class L_test_one_more extends L implements I_test_one_more {
  time = new L_test_one_more_time(`${this.__}.time`);
}
export interface I_test_one_more extends I {
  time: I_test_one_more_time;
}
export class L_test_one_more_time extends L implements I_test_one_more_time {
  get one() { return new L_test_one(`${this.__}.one`); }
  get two() { return new L_test_two(`${this.__}.two`); }
  get type() { return new L_test_type(`${this.__}.type`); }
}
export interface I_test_one_more_time extends I_test {
}
export class L_test_two extends L implements I_test_two {
  get no() { return new L_test_type_even_no(`${this.__}.no`); }
  get bad() { return new L_test_type_even_no_good(`${this.__}.no.good`); }
  timing = new L_test_two_timing(`${this.__}.timing`);
}
export interface I_test_two extends I_test_type_even {
  timing: I_test_two_timing;
}
export class L_test_two_timing extends L implements I_test_two_timing {
}
export interface I_test_two_timing extends I {
}
export class L_test_type extends L implements I_test_type {
  even = new L_test_type_even(`${this.__}.even`);
  odd = new L_test_type_odd(`${this.__}.odd`);
}
export interface I_test_type extends I {
  even: I_test_type_even;
  odd: I_test_type_odd;
}
export class L_test_type_even extends L implements I_test_type_even {
  no = new L_test_type_even_no(`${this.__}.no`);
  bad = new L_test_type_even_no_good(`${this.__}.no.good`);
}
export interface I_test_type_even extends I {
  no: I_test_type_even_no;
}
export type L_test_type_even_bad = L_test_type_even_no_good
export class L_test_type_even_no extends L implements I_test_type_even_no {
  good = new L_test_type_even_no_good(`${this.__}.good`);
}
export interface I_test_type_even_no extends I {
  good: I_test_type_even_no_good;
}
export class L_test_type_even_no_good extends L implements I_test_type_even_no_good {
}
export interface I_test_type_even_no_good extends I {
}
export class L_test_type_odd extends L implements I_test_type_odd {
  good = new L_test_type_odd_good(`${this.__}.good`);
}
export interface I_test_type_odd extends I {
  good: I_test_type_odd_good;
}
export class L_test_type_odd_good extends L implements I_test_type_odd_good {
}
export interface I_test_type_odd_good extends I {
}
export const test = new L_test("test");
