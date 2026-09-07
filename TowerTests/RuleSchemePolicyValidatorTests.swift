import XCTest
@testable import Tower

final class RuleSchemePolicyValidatorTests: XCTestCase {
    private func group(_ name: String, _ members: [RuleSchemeGroupMember]) -> RuleSchemeGroup {
        RuleSchemeGroup(name: name, kind: .select, members: members)
    }

    func testConditionalParametersStillValidateAfterCandidateRemoval() {
        let variants: [(String, [String: String])] = [
            ("quanx", ["ssid-members": "[\"DIRECT\",\"DIRECT\",\"Home:Removed\"]"]),
            ("surge", ["subnet-fields": "[\"default = DIRECT\",\"SSID:Home = Removed\"]"]),
            ("egern", ["default_policy": "DIRECT", "rules": "[{\"ssid\":{\"match\":\"Home\",\"policy\":\"Removed\"}}]"])
        ]
        for (format, parameters) in variants {
            let policy = RuleSchemeGroup(name: "Network", kind: .conditional,
                members: [.reference("DIRECT")], sourceFormat: format, parameters: parameters)
            let issues = RuleSchemePolicyValidator.validate(groups: [policy], ruleTargets: ["Network"], nodeNames: [])
            XCTAssertTrue(issues.contains(.init(code: .unknownGroupMember, names: ["Network", "Removed"])), format)
        }
    }

    func testConditionalMetadataCannotHideCycles() {
        let policy = RuleSchemeGroup(name: "Network", kind: .conditional,
            members: [.reference("DIRECT")], sourceFormat: "egern",
            parameters: ["default_policy": "Network", "rules": "[]"])
        let issues = RuleSchemePolicyValidator.validate(groups: [policy], ruleTargets: [], nodeNames: [])
        XCTAssertTrue(issues.contains(.init(code: .cycle, names: ["Network"])))
    }

    func testNativeRegexHonorsCaseSensitivity() {
        let policy = RuleSchemeGroup(name: "HK", kind: .select, members: [.nodePattern("^HK$")], sourceFormat: "quanx")
        let issues = RuleSchemePolicyValidator.validate(groups: [policy], ruleTargets: [], nodeNames: ["hk"])
        XCTAssertTrue(issues.contains(.init(code: .emptyGroup, names: ["HK"])))
    }

    func testDuplicatesAreReportedWithoutDictionaryTrap() {
        let issues = RuleSchemePolicyValidator.validate(
            groups: [group("A", [.reference("DIRECT")]), group("A", [.reference("REJECT")])],
            ruleTargets: ["A"], nodeNames: [])
        XCTAssertEqual(issues, [.init(code: .duplicateGroupName, names: ["A"])])
    }

    func testMissingReferencesIdentifyOwnerAndRuleTarget() {
        let issues = RuleSchemePolicyValidator.validate(
            groups: [group("A", [.reference("Missing"), .reference("DIRECT")])],
            ruleTargets: ["MissingRule", "MissingRule"], nodeNames: [])
        XCTAssertEqual(issues, [
            .init(code: .unknownGroupMember, names: ["A", "Missing"]),
            .init(code: .unknownRuleTarget, names: ["MissingRule"])
        ])
    }

    func testCyclesRemainInvalidEvenWithReachableNode() {
        let issues = RuleSchemePolicyValidator.validate(
            groups: [group("A", [.reference("B")]), group("B", [.reference("A"), .reference("Node")])],
            ruleTargets: ["A"], nodeNames: ["Node"])
        XCTAssertEqual(issues, [.init(code: .cycle, names: ["A", "B"])])
    }

    func testSelfReferenceAndEmptyGroupChain() {
        let issues = RuleSchemePolicyValidator.validate(
            groups: [group("Self", [.reference("Self")]), group("Parent", [.reference("Empty")]), group("Empty", [])],
            ruleTargets: [], nodeNames: [])
        XCTAssertTrue(issues.contains(.init(code: .cycle, names: ["Self"])))
        XCTAssertEqual(issues.filter { $0.code == .emptyGroup }.map(\.names), [["Self"], ["Parent"], ["Empty"]])
    }

    func testMatchingPatternsAndNestedGroupsPreserveOriginalUnicodeNames() {
        let issues = RuleSchemePolicyValidator.validate(
            groups: [group("Manual", [.reference("US")]), group("US", [.nodePattern("美国|us")])],
            ruleTargets: ["Manual", "🇺🇸 美国, 01", "REJECT-DROP", "direct"],
            nodeNames: ["🇺🇸 美国, 01", "US 02"])
        XCTAssertTrue(issues.isEmpty)
    }

    func testRemotePatternsCanBeUnresolvedButMalformedPatternsCannot() {
        let groups = [group("Remote", [.nodePattern("US")]), group("Broken", [.nodePattern("[")])]
        let local = RuleSchemePolicyValidator.validate(groups: groups, ruleTargets: [], nodeNames: [])
        XCTAssertTrue(local.contains(.init(code: .emptyGroup, names: ["Remote"])))
        let remote = RuleSchemePolicyValidator.validate(
            groups: groups, ruleTargets: [], nodeNames: [], allowUnresolvedPatterns: true)
        XCTAssertFalse(remote.contains(.init(code: .emptyGroup, names: ["Remote"])))
        XCTAssertTrue(remote.contains(.init(code: .invalidNodePattern, names: ["Broken", "["])))
        XCTAssertTrue(remote.contains(.init(code: .emptyGroup, names: ["Broken"])))
    }

    func testDeepGraphUsesIterativeTraversal() {
        let groups = (0..<4_000).map { index in
            group("G\(index)", [.reference(index == 3_999 ? "DIRECT" : "G\(index + 1)")])
        }
        XCTAssertTrue(RuleSchemePolicyValidator.validate(groups: groups, ruleTargets: ["G0"], nodeNames: []).isEmpty)
    }
}
