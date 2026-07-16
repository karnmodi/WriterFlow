import XCTest
@testable import WriterFlow

final class AzureModelsConfigTests: XCTestCase {
    func testAcceptsAzureResponsesEndpoints() {
        XCTAssertTrue(AzureModelsConfig.isUsableResponsesURL(
            "https://example.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview"
        ))
        XCTAssertTrue(AzureModelsConfig.isUsableResponsesURL(
            "https://example.openai.azure.com/openai/responses?api-version=2025-04-01-preview"
        ))
    }

    func testRejectsUntrustedOrMalformedEndpoints() {
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "http://example.openai.azure.com/openai/responses?api-version=2025-04-01-preview"
        ))
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "https://example.openai.azure.com.attacker.test/openai/responses?api-version=2025-04-01-preview"
        ))
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "https://example.openai.azure.com/openai/deployments?api-version=2025-04-01-preview"
        ))
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "https://user:password@example.openai.azure.com/openai/responses?api-version=2025-04-01-preview"
        ))
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "https://example.openai.azure.com/openai/responses"
        ))
        XCTAssertFalse(AzureModelsConfig.isUsableResponsesURL(
            "https://YOUR-RESOURCE.openai.azure.com/openai/responses?api-version=2025-04-01-preview"
        ))
    }
}
