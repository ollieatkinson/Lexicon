import Lexicon
import LexiconSearchONNX
import Testing
import Foundation

@Suite
struct ONNXSmokeTests {

	@Test
	func exportedProviderConformsWithoutLoadingAModel() {
		requireEmbeddingProvider(ONNXSearchEmbeddingProvider.self)
	}

	@Test
	func consumerLoadsInstalledRuntimeAndEmbeds() async throws {
		guard let modelRoot = ProcessInfo.processInfo.environment["LEXICON_ONNX_INTEGRATION_MODEL_ROOT"] else {
			return // macOS only checks downstream compilation; Linux CI requires runtime coverage.
		}
		let configuration = ONNXSearchModel.default
		let root = URL(fileURLWithPath: modelRoot)
		let provider = try ONNXSearchEmbeddingProvider(
			model: configuration.localModelURL(in: root),
			vocabulary: configuration.localVocabularyURL(in: root),
			configuration: configuration
		)
		let vectors = try await provider.embed(["consumer package runtime discovery"])
		#expect(vectors.count == 1)
		#expect(vectors.first?.count == configuration.dimensions)
	}

	private func requireEmbeddingProvider<Provider: Lexicon.Search.EmbeddingProvider>(
		_: Provider.Type
	) {}
}
