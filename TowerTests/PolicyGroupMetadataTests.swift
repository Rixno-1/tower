import XCTest
@testable import Tower

final class PolicyGroupMetadataTests: XCTestCase {
    func testLegacyGroupStillDecodesAndMetadataSurvivesCustomization() throws {
        let old = Data(#"{"name":"Auto","kind":"urlTest","members":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RuleSchemeGroup.self, from: old).kind, .urlTest)
        let group = RuleSchemeGroup(name: "Balance", kind: .loadBalance, members: [.reference("DIRECT")], algorithm: "round-robin", sourceType: "load-balance", sourceFormat: "clash", parameters: ["strategy": "round-robin"])
        let decoded = try JSONDecoder().decode(RuleSchemeGroup.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(decoded, group)
        XCTAssertEqual(RuleSchemeCustomization(schemeID: "test").applying(to: [group]).first, group)
    }
    func testConditionalPolicyRenameDoesNotRenameNetworkNames() {
        let group = RuleSchemeGroup(name: "Network", kind: .conditional, members: [.reference("Old")], parameters: ["ssid-members": "[\"Old\",\"Old\",\"Old:Old\"]"])
        XCTAssertEqual(group.renamedParameters { $0 == "Old" ? "New" : $0 }?["ssid-members"], "[\"New\",\"New\",\"Old:New\"]")
    }

    func testExplicitTypeChangeClearsIncompatibleSourceOptions() {
        let group = RuleSchemeGroup(name: "Balance", kind: .loadBalance, members: [.reference("DIRECT")], algorithm: "random", sourceType: "load-balance", sourceFormat: "surge", parameters: ["persistent": "false"])
        let customization = RuleSchemeCustomization(schemeID: "test", groupOverrides: ["Balance": RuleSchemeGroupOverride(kind: .select)])
        let changed = customization.applying(to: [group]).first
        XCTAssertEqual(changed?.kind, .select)
        XCTAssertNil(changed?.algorithm)
        XCTAssertNil(changed?.parameters)
    }

    func testReturningToOriginalTypeKeepsExplicitParameterReset() {
        let group = RuleSchemeGroup(name: "Choice", kind: .select, members: [.reference("DIRECT")], sourceFormat: "surge", parameters: ["no-alert": "true"])
        let customization = RuleSchemeCustomization(schemeID: "test", groupOverrides: ["Choice": .init(kind: .select, resetsSourceOptions: true)])
        XCTAssertNil(customization.applying(to: [group]).first?.parameters)
    }

    func testSubnetRenameTrimsPolicyWhitespaceAndQXPreservesPolicyColon() {
        let subnet = RuleSchemeGroup(name: "Net", kind: .conditional, members: [.reference("A")], parameters: ["subnet-fields": "[\"default = A\"]"])
        XCTAssertEqual(subnet.renamedParameters { $0 == "A" ? "B" : $0 }?["subnet-fields"], "[\"default =B\"]")
        let qx = RuleSchemeGroup(name: "Net", kind: .conditional, members: [.reference("Proxy:US")], parameters: ["ssid-members": "[\"DIRECT\",\"DIRECT\",\"Home:Proxy:US\"]"])
        XCTAssertEqual(qx.renamedParameters { $0 == "Proxy:US" ? "Proxy:JP" : $0 }?["ssid-members"], "[\"DIRECT\",\"DIRECT\",\"Home:Proxy:JP\"]")
    }

}
