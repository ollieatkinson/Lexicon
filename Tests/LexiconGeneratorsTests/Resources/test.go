package lexicon

type I interface {
	ID() string
	Localized() string
}

type L struct {
	id string
}

func (l L) ID() string {
	return l.id
}

func (l L) Localized() string {
	return l.id
}

var test = new_L_test("test")

type L_test struct {
	L
	one L_test_one
	two L_test_two
	type_ L_test_type_
}

func new_L_test(id string) L_test {
	l := L_test{L: L{id}}
	l.one = new_L_test_one(id + ".one")
	l.two = new_L_test_two(id + ".two")
	l.type_ = new_L_test_type_(id + ".type")
	return l
}

func (l L_test) Localized() string {
	return "test"
}

type L_test_one struct {
	L
	more L_test_one_more
}

func new_L_test_one(id string) L_test_one {
	l := L_test_one{L: L{id}}
	l.more = new_L_test_one_more(id + ".more")
	return l
}

func (l L_test_one) Localized() string {
	return "test.one"
}

func (l L_test_one) good() L_test_type__odd_good {
	return new_L_test_type__odd_good(l.id + ".good")
}

type L_test_one_more struct {
	L
	time L_test_one_more_time
}

func new_L_test_one_more(id string) L_test_one_more {
	l := L_test_one_more{L: L{id}}
	l.time = new_L_test_one_more_time(id + ".time")
	return l
}

func (l L_test_one_more) Localized() string {
	return "test.one.more"
}

type L_test_one_more_time struct {
	L
}

func new_L_test_one_more_time(id string) L_test_one_more_time {
	l := L_test_one_more_time{L: L{id}}
	return l
}

func (l L_test_one_more_time) Localized() string {
	return "test.one.more.time"
}

func (l L_test_one_more_time) one() L_test_one {
	return new_L_test_one(l.id + ".one")
}

func (l L_test_one_more_time) two() L_test_two {
	return new_L_test_two(l.id + ".two")
}

func (l L_test_one_more_time) type_() L_test_type_ {
	return new_L_test_type_(l.id + ".type")
}

type L_test_two struct {
	L
	timing L_test_two_timing
}

func new_L_test_two(id string) L_test_two {
	l := L_test_two{L: L{id}}
	l.timing = new_L_test_two_timing(id + ".timing")
	return l
}

func (l L_test_two) Localized() string {
	return "test.two"
}

func (l L_test_two) bad() L_test_type__even_bad {
	return new_L_test_type__even_no_good(l.id + ".no.good")
}

func (l L_test_two) no() L_test_type__even_no {
	return new_L_test_type__even_no(l.id + ".no")
}

type L_test_two_timing struct {
	L
}

func new_L_test_two_timing(id string) L_test_two_timing {
	l := L_test_two_timing{L: L{id}}
	return l
}

func (l L_test_two_timing) Localized() string {
	return "test.two.timing"
}

type L_test_type_ struct {
	L
	even L_test_type__even
	odd L_test_type__odd
}

func new_L_test_type_(id string) L_test_type_ {
	l := L_test_type_{L: L{id}}
	l.even = new_L_test_type__even(id + ".even")
	l.odd = new_L_test_type__odd(id + ".odd")
	return l
}

func (l L_test_type_) Localized() string {
	return "test.type"
}

type L_test_type__even struct {
	L
	no L_test_type__even_no
	bad L_test_type__even_bad
}

func new_L_test_type__even(id string) L_test_type__even {
	l := L_test_type__even{L: L{id}}
	l.no = new_L_test_type__even_no(id + ".no")
	l.bad = new_L_test_type__even_no_good(id + ".no.good")
	return l
}

func (l L_test_type__even) Localized() string {
	return "test.type.even"
}

type L_test_type__even_bad = L_test_type__even_no_good

type L_test_type__even_no struct {
	L
	good L_test_type__even_no_good
}

func new_L_test_type__even_no(id string) L_test_type__even_no {
	l := L_test_type__even_no{L: L{id}}
	l.good = new_L_test_type__even_no_good(id + ".good")
	return l
}

func (l L_test_type__even_no) Localized() string {
	return "test.type.even.no"
}

type L_test_type__even_no_good struct {
	L
}

func new_L_test_type__even_no_good(id string) L_test_type__even_no_good {
	l := L_test_type__even_no_good{L: L{id}}
	return l
}

func (l L_test_type__even_no_good) Localized() string {
	return "test.type.even.no.good"
}

type L_test_type__odd struct {
	L
	good L_test_type__odd_good
}

func new_L_test_type__odd(id string) L_test_type__odd {
	l := L_test_type__odd{L: L{id}}
	l.good = new_L_test_type__odd_good(id + ".good")
	return l
}

func (l L_test_type__odd) Localized() string {
	return "test.type.odd"
}

type L_test_type__odd_good struct {
	L
}

func new_L_test_type__odd_good(id string) L_test_type__odd_good {
	l := L_test_type__odd_good{L: L{id}}
	return l
}

func (l L_test_type__odd_good) Localized() string {
	return "test.type.odd.good"
}
