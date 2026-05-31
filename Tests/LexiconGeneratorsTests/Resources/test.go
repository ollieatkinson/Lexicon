package lexicon

type I interface {
	ID() string
	Localized() string
}

type Lemma string

func l(path string) Lemma {
	return Lemma(path)
}

func (l Lemma) ID() string {
	return string(l)
}

func (l Lemma) Localized() string {
	return string(l)
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

var Test = new_L_test("test")

type L_test struct {
	L
	One L_test_one
	Two L_test_two
	Type L_test_type
}

func new_L_test(id string) L_test {
	l := L_test{L: L{id}}
	l.One = new_L_test_one(id + ".one")
	l.Two = new_L_test_two(id + ".two")
	l.Type = new_L_test_type(id + ".type")
	return l
}

func (l L_test) Localized() string {
	return "test"
}

type L_test_one struct {
	L
	More L_test_one_more
}

func new_L_test_one(id string) L_test_one {
	l := L_test_one{L: L{id}}
	l.More = new_L_test_one_more(id + ".more")
	return l
}

func (l L_test_one) Localized() string {
	return "test.one"
}

func (l L_test_one) Good() L_test_type_odd_good {
	return new_L_test_type_odd_good(l.id + ".good")
}

type L_test_one_more struct {
	L
	Time L_test_one_more_time
}

func new_L_test_one_more(id string) L_test_one_more {
	l := L_test_one_more{L: L{id}}
	l.Time = new_L_test_one_more_time(id + ".time")
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

func (l L_test_one_more_time) One() L_test_one {
	return new_L_test_one(l.id + ".one")
}

func (l L_test_one_more_time) Two() L_test_two {
	return new_L_test_two(l.id + ".two")
}

func (l L_test_one_more_time) Type() L_test_type {
	return new_L_test_type(l.id + ".type")
}

type L_test_two struct {
	L
	Timing L_test_two_timing
}

func new_L_test_two(id string) L_test_two {
	l := L_test_two{L: L{id}}
	l.Timing = new_L_test_two_timing(id + ".timing")
	return l
}

func (l L_test_two) Localized() string {
	return "test.two"
}

func (l L_test_two) Bad() L_test_type_even_bad {
	return new_L_test_type_even_no_good(l.id + ".no.good")
}

func (l L_test_two) No() L_test_type_even_no {
	return new_L_test_type_even_no(l.id + ".no")
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

type L_test_type struct {
	L
	Even L_test_type_even
	Odd L_test_type_odd
}

func new_L_test_type(id string) L_test_type {
	l := L_test_type{L: L{id}}
	l.Even = new_L_test_type_even(id + ".even")
	l.Odd = new_L_test_type_odd(id + ".odd")
	return l
}

func (l L_test_type) Localized() string {
	return "test.type"
}

type L_test_type_even struct {
	L
	No L_test_type_even_no
	Bad L_test_type_even_bad
}

func new_L_test_type_even(id string) L_test_type_even {
	l := L_test_type_even{L: L{id}}
	l.No = new_L_test_type_even_no(id + ".no")
	l.Bad = new_L_test_type_even_no_good(id + ".no.good")
	return l
}

func (l L_test_type_even) Localized() string {
	return "test.type.even"
}

type L_test_type_even_bad = L_test_type_even_no_good

type L_test_type_even_no struct {
	L
	Good L_test_type_even_no_good
}

func new_L_test_type_even_no(id string) L_test_type_even_no {
	l := L_test_type_even_no{L: L{id}}
	l.Good = new_L_test_type_even_no_good(id + ".good")
	return l
}

func (l L_test_type_even_no) Localized() string {
	return "test.type.even.no"
}

type L_test_type_even_no_good struct {
	L
}

func new_L_test_type_even_no_good(id string) L_test_type_even_no_good {
	l := L_test_type_even_no_good{L: L{id}}
	return l
}

func (l L_test_type_even_no_good) Localized() string {
	return "test.type.even.no.good"
}

type L_test_type_odd struct {
	L
	Good L_test_type_odd_good
}

func new_L_test_type_odd(id string) L_test_type_odd {
	l := L_test_type_odd{L: L{id}}
	l.Good = new_L_test_type_odd_good(id + ".good")
	return l
}

func (l L_test_type_odd) Localized() string {
	return "test.type.odd"
}

type L_test_type_odd_good struct {
	L
}

func new_L_test_type_odd_good(id string) L_test_type_odd_good {
	l := L_test_type_odd_good{L: L{id}}
	return l
}

func (l L_test_type_odd_good) Localized() string {
	return "test.type.odd.good"
}
