import XCTest
@testable import Tower

final class RuleSchemeImportNameTests: XCTestCase {
    func testGitHubFileNameKeepsExtensionAfterRawRewrite() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/yyhhyyyyyy/selfproxy/blob/main/Surge/Surge-Mac.conf"))
        XCTAssertEqual(RuleSchemeImportService.defaultName(for: url), "Surge-Mac.conf")
    }

    func testEncodedFilenameIgnoresQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/%E8%A7%84%E5%88%99%20Mac.yaml?token=fixture#section"))
        XCTAssertEqual(RuleSchemeImportService.defaultName(for: url), "规则 Mac.yaml")
    }

    func testDirectoryFallsBackToHost() throws {
        XCTAssertEqual(RuleSchemeImportService.defaultName(for: try XCTUnwrap(URL(string: "https://example.com/rules/"))), "example.com")
    }
}
