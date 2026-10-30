import Lexicon
import LexiconSearchONNX
import Testing

@Suite
struct ONNXSmokeTests {

	@Test
	func exportedProviderConformsWithoutLoadingAModel() {
		requireEmbeddingProvider(ONNXSearchEmbeddingProvider.self)
	}

	private func requireEmbeddingProvider<Provider: Lexicon.Search.EmbeddingProvider>(
		_: Provider.Type
	) {}
}
