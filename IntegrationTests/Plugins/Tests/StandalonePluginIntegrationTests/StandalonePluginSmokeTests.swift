import StandalonePluginFixture
import Testing

@Suite
struct StandalonePluginSmokeTests {

	@Test
	@LexiconActor
	func oneNestedInputProducesAStandaloneModule() {
		#expect(standalone.__ == "standalone")
		#expect(standalone.imported.__ == "standalone.imported")
	}
}
