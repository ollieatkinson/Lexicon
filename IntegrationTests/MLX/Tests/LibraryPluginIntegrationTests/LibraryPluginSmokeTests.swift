import LibraryPluginFixture
import Lexicon
import Testing

@Suite
struct LibraryPluginSmokeTests {

	@Test
	@LexiconActor
	func sameNamedNestedInputsProduceDistinctSources() {
		#expect(north.__ == "north")
		#expect(south.__ == "south")
	}
}
