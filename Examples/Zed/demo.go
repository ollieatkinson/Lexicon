package main

type Lemma string

func l(path string) Lemma {
	return Lemma(path)
}

var valid = l("test.type.even.bad")
var invalid = l("test.type.even.bed")
var completeHere = l("test.type.even.")
