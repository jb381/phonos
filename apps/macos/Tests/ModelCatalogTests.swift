import XCTest
@testable import Phonos

final class ModelCatalogTests: XCTestCase {

    // MARK: - description(for:)

    func testDescriptionForTinyEn() {
        let desc = ModelCatalog.description(for: "tiny.en")
        XCTAssertEqual(desc, "Fastest, lowest memory; good for short dictation.")
    }

    func testDescriptionForBaseEn() {
        let desc = ModelCatalog.description(for: "base.en")
        XCTAssertEqual(desc, "Fast and lightweight; balanced default for most Macs.")
    }

    func testDescriptionForSmallEn() {
        let desc = ModelCatalog.description(for: "small.en")
        XCTAssertEqual(desc, "Better accuracy with moderate CPU and memory cost.")
    }

    func testDescriptionForMediumEn() {
        let desc = ModelCatalog.description(for: "medium.en")
        XCTAssertEqual(desc, "Higher accuracy; noticeably slower on CPU.")
    }

    func testDescriptionForTurbo() {
        let desc = ModelCatalog.description(for: "turbo")
        XCTAssertEqual(desc, "Speed-optimized multilingual model.")
    }

    func testDescriptionForDistilLargeV3() {
        let desc = ModelCatalog.description(for: "distil-large-v3")
        XCTAssertEqual(desc, "Strong quality with lower cost than large-v3.")
    }

    func testDescriptionForLargeV3() {
        let desc = ModelCatalog.description(for: "large-v3")
        XCTAssertEqual(desc, "Highest quality; slow and memory-heavy on CPU.")
    }

    func testDescriptionForUnknownModelReturnsDefault() {
        let desc = ModelCatalog.description(for: "some-future-model")
        XCTAssertEqual(desc, "Custom configured model.")
    }

    func testDescriptionForEmptyStringReturnsDefault() {
        let desc = ModelCatalog.description(for: "")
        XCTAssertEqual(desc, "Custom configured model.")
    }

    // MARK: - isLargeCPUModel(_:)

    func testIsLargeCPUModelForMediumEn() {
        XCTAssertTrue(ModelCatalog.isLargeCPUModel("medium.en"))
    }

    func testIsLargeCPUModelForLargeV3() {
        XCTAssertTrue(ModelCatalog.isLargeCPUModel("large-v3"))
    }

    func testIsLargeCPUModelForTinyEn() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("tiny.en"))
    }

    func testIsLargeCPUModelForBaseEn() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("base.en"))
    }

    func testIsLargeCPUModelForSmallEn() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("small.en"))
    }

    func testIsLargeCPUModelForTurbo() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("turbo"))
    }

    func testIsLargeCPUModelForDistilLargeV3() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("distil-large-v3"))
    }

    func testIsLargeCPUModelForUnknownModel() {
        XCTAssertFalse(ModelCatalog.isLargeCPUModel("some-future-model"))
    }

    // MARK: - Data integrity

    func testAllKnownModelsHaveUniqueDescriptions() {
        let knownModels = ["tiny.en", "base.en", "small.en", "medium.en", "turbo", "distil-large-v3", "large-v3"]
        let descriptions = knownModels.map { ModelCatalog.description(for: $0) }
        XCTAssertEqual(Set(descriptions).count, knownModels.count, "Each known model should have a unique description")
    }

    func testAllKnownModelsHaveNonEmptyDescriptions() {
        let knownModels = ["tiny.en", "base.en", "small.en", "medium.en", "turbo", "distil-large-v3", "large-v3"]
        for model in knownModels {
            let desc = ModelCatalog.description(for: model)
            XCTAssertFalse(desc.isEmpty, "Model \(model) should have a non-empty description")
        }
    }

    func testLargeCPUModelListMatchesCatalogDescriptions() {
        let catalogLargeModels = ["tiny.en", "base.en", "small.en", "medium.en", "turbo", "distil-large-v3", "large-v3", "unknown"].filter {
            ModelCatalog.isLargeCPUModel($0)
        }
        let expectedLarge = ["medium.en", "large-v3"]
        XCTAssertEqual(catalogLargeModels, expectedLarge, "isLargeCPUModel should only return true for the models that are described as slow/heavy")
    }
}
