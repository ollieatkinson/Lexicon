import Lexicon
import LexiconSearchMLX
import Testing

@Suite
struct MLXSmokeTests {

	@Test
	func exportedProviderConformsWithoutLoadingAModel() {
		requireEmbeddingProvider(MLXSearchEmbeddingProvider.self)
	}

	private func requireEmbeddingProvider<Provider: Lexicon.Search.EmbeddingProvider>(
		_: Provider.Type
	) {}
}
