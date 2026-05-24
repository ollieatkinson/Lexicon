//
// github.com/screensailor 2026
//

@_exported import Hope
@testable import LexiconGenerators

final class SourceIdentifierTests: Hopes {

	func test_stand_alone_type_suffix_preserves_existing_identifier_rules() {
		hope("test.one.more".standAloneTypeSuffix) == "test_one_more"
		hope("test.type_even.no_good".standAloneTypeSuffix) == "test_type__even_no__good"
		hope("test._&_.type".standAloneTypeSuffix) == "test_____type"
	}
}
