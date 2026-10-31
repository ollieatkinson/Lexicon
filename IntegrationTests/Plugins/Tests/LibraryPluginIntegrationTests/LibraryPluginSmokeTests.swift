import LibraryPluginFixture
import Lexicon
import Testing

@Suite
struct LibraryPluginSmokeTests {

	@Test
	@LexiconActor
	func sameNamedNestedInputsProduceDistinctSources() {
		#expect(north.__ == "north")
		#expect(north.imported.__ == "north.imported")
		#expect(south.__ == "south")
	}
}
