import Foundation
import CryptoKit

enum RuleSchemeParseError: LocalizedError, Equatable {
    case notReadableText
    case noGroups
    case noRulesets
    case unsupportedSyntax

    var errorDescription: String? {
        switch self {
        case .notReadableText: String(localized: "规则配置不是可识别的文本")
        case .noGroups: String(localized: "配置里没有找到可识别的策略组")
        case .noRulesets: String(localized: "配置里没有找到可识别的规则")
        case .unsupportedSyntax: String(localized: "配置包含无法安全转换的语法")
        }
    }
}

/// Reads the subconverter remote-config `.ini` dialect used by ACL4SSR.
///
/// Two directives matter:
///
///     ruleset=<组名>,<https 规则列表地址>
///     ruleset=<组名>,[]<直接写出的规则>
///     custom_proxy_group=<组名>`<类型>`<成员>`…[`<测试地址>`<间隔,超时,容差>]
///
/// A member written as `[]名称` references another group or a builtin policy;
/// anything else is a regular expression matched against node names.
struct RuleSchemeParser {
    /// Exact URL identity; do not retain subscription credentials in template metadata.
    static func sourceURLHash(_ url: String) -> String {
        SHA256.hash(data: Data(url.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Restore source semantics discarded by legacy parsers. Metadata-bearing
    /// groups are already current and must never be overwritten by old source.
    /// User graph overrides are stored separately and remain untouched.
    func restoringLegacySmartGroups(in scheme: RuleScheme) -> RuleScheme {
        guard !scheme.isBundled,
              scheme.groups.contains(where: { $0.sourceType == nil }),
              let source = scheme.rawConfigurationText,
              let reparsed = try? parse(text: source, id: scheme.id, name: scheme.name,
                                       summary: scheme.summary) else { return scheme }
        let existing = Dictionary(scheme.groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var restored = scheme
        restored.groups = reparsed.groups.map { parsed in
            if let old = existing[parsed.name], old.sourceType != nil { return old }
            return parsed
        }
        // Preserve groups created after the retained source was captured.
        let parsedNames = Set(reparsed.groups.map(\.name))
        restored.groups += scheme.groups.filter { !parsedNames.contains($0.name) }
        restored.rulesets = reparsed.rulesets
        return restored
    }

    func parse(
        data: Data,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        isBundled: Bool = false
    ) throws -> RuleScheme {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw RuleSchemeParseError.notReadableText
        }
        return try parse(
            text: text,
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            isBundled: isBundled
        )
    }

    func parse(
        text: String,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        isBundled: Bool = false
    ) throws -> RuleScheme {
        let networkSettings = parseNetworkSettings(in: text)
        if text.lowercased().contains("[policy]") {
            return try nativeScheme(text: text, id: id, name: name, summary: summary,
                                    sourceURLString: sourceURLString, isBundled: isBundled, format: "quanx")
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            let format = object?["proxy-groups"] != nil ? "clash" : object?["policy_groups"] != nil ? "egern" : "sing-box"
            return try nativeScheme(text: text, id: id, name: name, summary: summary,
                                    sourceURLString: sourceURLString, isBundled: isBundled, format: format)
        }
        let clashHeader = text.range(of: #"(?m)^\s*['"]?proxy-groups['"]?\s*:"#, options: .regularExpression) != nil
        let egernHeader = text.range(of: #"(?m)^\s*['"]?policy_groups['"]?\s*:"#, options: .regularExpression) != nil
        if clashHeader || egernHeader {
            return try nativeScheme(text: text, id: id, name: name, summary: summary,
                                    sourceURLString: sourceURLString, isBundled: isBundled,
                                    format: egernHeader ? "egern" : "clash")
        }

        // A complete Surge configuration carries the same information in
        // [Proxy Group] and [Rule] that a subconverter config puts in
        // custom_proxy_group= and ruleset=, so both are accepted.
        if !text.contains("custom_proxy_group="), text.lowercased().contains("[proxy group]") {
            return try parseSurgeConfiguration(
                text: text,
                id: id,
                name: name,
                summary: summary,
                sourceURLString: sourceURLString,
                networkSettings: networkSettings,
                isBundled: isBundled
            )
        }

        var groups: [RuleSchemeGroup] = []
        var rulesets: [RuleSchemeRuleset] = []
        var metadata: [String: RuleSchemeGroup] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // `;` and `#` start comments, and `[custom]` is a section header.
            guard !line.isEmpty,
                  !line.hasPrefix(";"),
                  !line.hasPrefix("#"),
                  !line.hasPrefix("[") else { continue }

            if let encoded = value(of: "tower_group_metadata", in: line) {
                guard let data = Data(base64Encoded: encoded),
                      let group = try? JSONDecoder().decode(RuleSchemeGroup.self, from: data),
                      metadata[group.name] == nil else { throw RuleSchemeParseError.unsupportedSyntax }
                metadata[group.name] = group
            } else if let value = value(of: "ruleset", in: line) {
                if let ruleset = parseRuleset(value) { rulesets.append(ruleset) }
            } else if let value = value(of: "custom_proxy_group", in: line) {
                if let group = parseGroup(value) { groups.append(group) }
            }
        }

        groups = groups.map { group in
            guard let saved = metadata[group.name], saved.kind == group.kind,
                  saved.members == group.members else { return group }
            return RuleSchemeGroup(name: group.name, kind: group.kind, members: group.members,
                                   testURLString: group.testURLString, interval: group.interval, tolerance: group.tolerance,
                                   algorithm: saved.algorithm, sourceType: saved.sourceType, sourceFormat: saved.sourceFormat,
                                   parameters: saved.parameters)
        }
        guard !groups.isEmpty else { throw RuleSchemeParseError.noGroups }
        guard !rulesets.isEmpty else { throw RuleSchemeParseError.noRulesets }

        return RuleScheme(
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            groups: groups,
            rulesets: rulesets,
            rawConfigurationText: RuleSchemeSourceSanitizer.persistableText(text),
            networkSettings: networkSettings,
            updatedAt: .now,
            isBundled: isBundled
        )
    }

    private func nativeKind(_ raw: String) -> RuleSchemeGroup.Kind {
        switch raw.lowercased() {
        case "select", "static", "selector": .select
        case "url-test", "urltest", "auto_test", "url-latency-benchmark": .urlTest
        case "fallback", "available": .fallback
        case "load-balance", "load_balance", "loadbalance", "round-robin", "dest-hash": .loadBalance
        case "smart": .smart
        case "conditional", "subnet", "ssid": .conditional
        case "relay": .relay
        default: .unsupported
        }
    }

    private func parameterFields(_ fields: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for field in fields {
            guard let equal = field.firstIndex(of: "=") else { continue }
            result[String(field[..<equal]).trimmingCharacters(in: .whitespaces)] =
                unquotedYAMLScalar(String(field[field.index(after: equal)...]).trimmingCharacters(in: .whitespaces))
        }
        return result
    }

    private func nativeScheme(text: String, id: String, name: String, summary: String,
                              sourceURLString: String?, isBundled: Bool, format: String) throws -> RuleScheme {
        var drafts: [(String, String, [String], [String: Any])] = []
        var sourceBindings: [String: String] = [:]
        var rules: [RuleSchemeRuleset] = []
        func string(_ value: Any?) -> String? {
            if let text = value as? String { return text }
            if let number = value as? NSNumber {
                if String(cString: number.objCType) == "c" { return number.boolValue ? "true" : "false" }
                return number.stringValue
            }
            return nil
        }
        func strings(_ value: Any?) -> [String] {
            if let values = value as? [String] { return values }
            return string(value).map { [$0] } ?? []
        }
        if format == "quanx" {
            var section = ""
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") { section = line.lowercased(); continue }
                guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"), !line.hasPrefix("//") else { continue }
                if section == "[policy]", let equal = line.firstIndex(of: "=") {
                    let type = line[..<equal].trimmingCharacters(in: .whitespaces).lowercased()
                    let fields = surgeFields(String(line[line.index(after: equal)...]))
                    guard let name = fields.first, !name.isEmpty else { throw RuleSchemeParseError.unsupportedSyntax }
                    drafts.append((unquotedYAMLScalar(name), type,
                                   fields.dropFirst().filter { !$0.contains("=") }.map(unquotedYAMLScalar),
                                   parameterFields(Array(fields.dropFirst()))))
                } else if section == "[server_remote]" {
                    let fields = surgeFields(line)
                    let parameters = parameterFields(Array(fields.dropFirst()))
                    if parameters["enabled"] == "false" { continue }
                    guard let address = fields.first, let url = URL(string: address),
                          ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                          let tag = parameters["tag"], !tag.isEmpty,
                          sourceBindings[tag] == nil else { throw RuleSchemeParseError.unsupportedSyntax }
                    sourceBindings[tag] = Self.sourceURLHash(address)
                } else if section == "[filter_local]" {
                    let fields = surgeFields(line)
                    let types = ["host": "DOMAIN", "host-suffix": "DOMAIN-SUFFIX", "host-keyword": "DOMAIN-KEYWORD", "host-wildcard": "DOMAIN-WILDCARD", "ip-asn": "IP-ASN", "ip-cidr": "IP-CIDR", "ip6-cidr": "IP-CIDR6", "geoip": "GEOIP", "final": "FINAL"]
                    guard let first = fields.first, let type = types[first.lowercased()] else { throw RuleSchemeParseError.unsupportedSyntax }
                    if let rule = parseSurgeRuleLine(([type] + fields.dropFirst()).joined(separator: ",")) { rules.append(rule) }
                } else if section == "[filter_remote]" {
                    let fields = surgeFields(line)
                    let params = parameterFields(Array(fields.dropFirst()))
                    if params["enabled"] == "false" { continue }
                    guard let address = fields.first, let url = URL(string: address), url.scheme == "https",
                          let policy = params["force-policy"] else { throw RuleSchemeParseError.unsupportedSyntax }
                    rules.append(.init(groupName: policy, resource: .remote(url)))
                }
            }
        } else {
            let root: [String: Any]
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw RuleSchemeParseError.unsupportedSyntax }
                root = object
            } else {
                var reader = SchemeYAMLReader(text)
                guard let object = try reader.read() as? [String: Any] else { throw RuleSchemeParseError.unsupportedSyntax }
                root = object
            }
            if format == "clash" {
                for (name, provider) in root["proxy-providers"] as? [String: [String: Any]] ?? [:] {
                    if let address = string(provider["url"]) { sourceBindings[name] = Self.sourceURLHash(address) }
                }
                for item in root["proxy-groups"] as? [[String: Any]] ?? [] {
                    guard let name = string(item["name"]), let type = string(item["type"]) else { throw RuleSchemeParseError.unsupportedSyntax }
                    drafts.append((name, type, strings(item["proxies"]), item))
                }
                let providers = root["rule-providers"] as? [String: [String: Any]] ?? [:]
                for raw in strings(root["rules"]) {
                    let fields = surgeFields(raw)
                    if fields.first?.uppercased() == "RULE-SET", fields.count >= 3 {
                        guard let address = string(providers[fields[1]]?["url"]), let url = URL(string: address), url.scheme == "https" else { throw RuleSchemeParseError.unsupportedSyntax }
                        rules.append(.init(groupName: fields[2], resource: .remote(url)))
                    } else {
                        let canonical = fields.first?.uppercased() == "MATCH" ? (["FINAL"] + fields.dropFirst()).joined(separator: ",") : raw
                        guard let rule = parseSurgeRuleLine(canonical) else { throw RuleSchemeParseError.unsupportedSyntax }
                        rules.append(rule)
                    }
                }
            } else if format == "egern" {
                for wrapper in root["policy_groups"] as? [[String: Any]] ?? [] {
                    guard wrapper.count == 1, let type = wrapper.keys.first, let item = wrapper[type] as? [String: Any], let name = string(item["name"]) else { throw RuleSchemeParseError.unsupportedSyntax }
                    drafts.append((name, type, strings(item["policies"]), item))
                }
                let types = ["domain": "DOMAIN", "domain_suffix": "DOMAIN-SUFFIX", "domain_keyword": "DOMAIN-KEYWORD", "ip_cidr": "IP-CIDR", "ip_cidr6": "IP-CIDR6", "geoip": "GEOIP"]
                for wrapper in root["rules"] as? [[String: Any]] ?? [] {
                    guard wrapper.count == 1, let type = wrapper.keys.first else { throw RuleSchemeParseError.unsupportedSyntax }
                    if type == "default", let policy = string(wrapper[type]) { rules.append(.init(groupName: policy, resource: .inline("FINAL"))); continue }
                    guard let item = wrapper[type] as? [String: Any], let policy = string(item["policy"]) else { throw RuleSchemeParseError.unsupportedSyntax }
                    if string(item["disabled"]) == "true" { continue }
                    if type == "default" { rules.append(.init(groupName: policy, resource: .inline("FINAL"))); continue }
                    if type == "rule_set", let urlText = string(item["match"]), let url = URL(string: urlText), url.scheme == "https" {
                        rules.append(.init(groupName: policy, resource: .remote(url)))
                    } else if let ruleType = types[type], let value = string(item["match"]) {
                        rules.append(.init(groupName: policy, resource: .inline("\(ruleType),\(value)" + (string(item["no_resolve"]) == "true" ? ",no-resolve" : ""))))
                    } else { throw RuleSchemeParseError.unsupportedSyntax }
                }
            } else {
                for item in root["outbounds"] as? [[String: Any]] ?? [] {
                    guard let type = string(item["type"]), let name = string(item["tag"]) else { continue }
                    if item["outbounds"] != nil || ["selector", "urltest"].contains(type) {
                        drafts.append((name, type, strings(item["outbounds"]), item))
                    }
                }
                let route = root["route"] as? [String: Any] ?? [:]
                let types = ["domain": "DOMAIN", "domain_suffix": "DOMAIN-SUFFIX", "domain_keyword": "DOMAIN-KEYWORD", "ip_cidr": "IP-CIDR"]
                for item in route["rules"] as? [[String: Any]] ?? [] {
                    guard let policy = string(item["outbound"]), item["action"] == nil || string(item["action"]) == "route" else { throw RuleSchemeParseError.unsupportedSyntax }
                    let conditions = item.keys.filter { !["outbound", "action"].contains($0) }
                    guard conditions.count == 1, let key = conditions.first, let type = types[key] else { throw RuleSchemeParseError.unsupportedSyntax }
                    for value in strings(item[key]) { rules.append(.init(groupName: policy, resource: .inline("\(type),\(value)"))) }
                }
                if let final = string(route["final"]) { rules.append(.init(groupName: final, resource: .inline("FINAL"))) }
            }
        }
        let names = Set(drafts.map { $0.0 })
        let groups = drafts.map { name, type, candidates, item -> RuleSchemeGroup in
            var parameters: [String: String] = [:]
            for (key, value) in item {
                if key == "urls" { continue }
                if let scalar = string(value) { parameters[key] = scalar }
                else if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let encoded = String(data: data, encoding: .utf8) { parameters[key] = encoded }
            }
            var bindings = sourceBindings
            if format == "egern", !strings(item["urls"]).isEmpty {
                let hashes = strings(item["urls"]).map(Self.sourceURLHash)
                bindings = Dictionary(hashes.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
                if let data = try? JSONSerialization.data(withJSONObject: hashes),
                   let json = String(data: data, encoding: .utf8) { parameters["tower-source-tags"] = json }
            }
            if !bindings.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: bindings, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) { parameters["tower-source-bindings"] = json }
            if type == "ssid", let data = try? JSONSerialization.data(withJSONObject: candidates),
               let encoded = String(data: data, encoding: .utf8) { parameters["ssid-members"] = encoded }
            var members = candidates.map { candidate -> RuleSchemeGroupMember in
                let builtins = ["direct": "DIRECT", "reject": "REJECT", "reject-drop": "REJECT-DROP"]
                if let builtin = builtins[candidate.lowercased()] { return .reference(builtin) }
                return names.contains(candidate) ? .reference(candidate) : .nodePattern("^\(NSRegularExpression.escapedPattern(for: candidate))$")
            }
            if nativeKind(type) == .conditional {
                var policies: [String] = []
                if type == "ssid" {
                    policies = candidates.enumerated().map { offset, value in
                        offset < 2 ? value : value.components(separatedBy: ":").dropFirst().joined(separator: ":")
                    }
                } else {
                    policies = (item["rules"] as? [[String: Any]] ?? []).compactMap { wrapper in
                        guard let nested = wrapper.values.first as? [String: Any] else { return nil }
                        return string(nested["policy"])
                    }
                    if let fallback = string(item["default_policy"]) { policies.append(fallback) }
                }
                members = unique(policies.filter { !$0.isEmpty }).map { .reference($0) }
            }
            var sourcePatterns: [String] = []
            if let filter = parameters["server-tag-regex"] {
                members.append(.nodePattern(filter))
                if parameters["resource-tag-regex"] != nil { sourcePatterns.append(filter) }
            } else if parameters["resource-tag-regex"] != nil {
                members.append(.nodePattern(".*"))
                sourcePatterns.append(".*")
            }
            if item["use"] != nil || item["urls"] != nil || parameters["include-all"] == "true" || parameters["include-all-proxies"] == "true" {
                let pattern = parameters["filter"] ?? ".*"
                members.append(.nodePattern(pattern))
                sourcePatterns.append(pattern)
            }
            if !sourcePatterns.isEmpty, let data = try? JSONSerialization.data(withJSONObject: sourcePatterns),
               let json = String(data: data, encoding: .utf8) { parameters["tower-source-patterns"] = json }
            var interval = parameters["interval"].flatMap(Int.init) ?? parameters["check-interval"].flatMap(Int.init)
            if format == "sing-box", let duration = parameters["interval"], let seconds = nativeDuration(duration) { interval = seconds }
            let algorithm = parameters["algorithm"] ?? parameters["strategy"] ?? (["round-robin", "dest-hash"].contains(type) ? type : nil)
            let effectiveType = format == "egern" && type == "external" ? (parameters["type"] ?? "select") : type
            return RuleSchemeGroup(name: name, kind: nativeKind(effectiveType), members: members,
                                   testURLString: parameters["url"] ?? parameters["latency_test_url"], interval: interval,
                                   tolerance: parameters["tolerance"].flatMap(Int.init),
                                   algorithm: algorithm, sourceType: type, sourceFormat: format, parameters: parameters)
        }
        guard !groups.isEmpty else { throw RuleSchemeParseError.noGroups }
        guard !rules.isEmpty else { throw RuleSchemeParseError.noRulesets }
        return RuleScheme(id: id, name: name, summary: summary, sourceURLString: sourceURLString,
                          groups: groups, rulesets: rules, rawConfigurationText: format == "clash" && !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ? RuleSchemeSourceSanitizer.persistableText(text) : nil,
                          networkSettings: parseNetworkSettings(in: text), updatedAt: .now, isBundled: isBundled)
    }

    private func nativeDuration(_ value: String) -> Int? {
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600]
        var number = "", total = 0.0
        for character in value {
            if character.isNumber || character == "." { number.append(character) }
            else if let multiplier = units[character], let parsed = Double(number) { total += parsed * multiplier; number = "" }
            else { return nil }
        }
        guard number.isEmpty, total.isFinite, total >= 0, total < Double(Int.max) else { return nil }
        return Int(total)
    }

    // MARK: - Clash YAML

    private func yamlScalar(after key: String, in line: String) -> String {
        unquotedYAMLScalar(
            String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        )
    }

    private func unquotedYAMLScalar(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" || first == "'"),
              first == last else { return value }
        return String(value.dropFirst().dropLast())
    }

    private func value(of key: String, in line: String) -> String? {
        let prefix = "\(key)="
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Surge configuration

    /// Reads `[Proxy Group]` and `[Rule]` out of a complete Surge config.
    ///
    /// The other sections are deliberately ignored: `[Proxy]` holds nodes,
    /// which arrive through subscriptions instead, and `[URL Rewrite]`,
    /// `[Script]`, `[MITM]` and `[Host]` have no equivalent in Tower's model.
    private func parseSurgeConfiguration(
        text: String,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String?,
        networkSettings: RuleSchemeNetworkSettings?,
        isBundled: Bool
    ) throws -> RuleScheme {
        var section = ""
        var groupLines: [(name: String, kind: RuleSchemeGroup.Kind, fields: [String], sourceType: String)] = []
        var ruleLines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"), !line.hasPrefix("//") else {
                continue
            }
            if line.hasPrefix("[") {
                section = line.lowercased()
                continue
            }

            switch section {
            case "[proxy group]":
                if let group = parseSurgeGroupLine(line) { groupLines.append(group) }
            case "[proxy chain]":
                if let equal = line.firstIndex(of: "=") {
                    let name = String(line[..<equal]).trimmingCharacters(in: .whitespaces)
                    let fields = surgeFields(String(line[line.index(after: equal)...]))
                    groupLines.append((name, .relay, fields, "chain"))
                }
            case "[rule]":
                ruleLines.append(line)
            default:
                continue
            }
        }

        guard !groupLines.isEmpty else { throw RuleSchemeParseError.noGroups }

        let groupNames = Set(groupLines.map(\.name))
        // External node URLs in rule templates are placeholders. As with other
        // imported rule formats, bind their node pool to Tower's chosen nodes;
        // never fetch the template's policy-path as an implicit subscription.
        func patterns(in name: String, visiting: Set<String>) -> [String] {
            guard !visiting.contains(name), let entry = groupLines.first(where: { $0.name == name }) else {
                return []
            }
            let visiting = visiting.union([name])
            var explicit: [String] = []
            var result: [String] = []
            var filter: String?
            for field in entry.fields {
                if let separator = field.firstIndex(of: "=") {
                    let key = field[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = String(field[field.index(after: separator)...])
                        .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    switch key {
                    case "policy-path": result.append(".*")
                    case "include-all-proxies" where value.lowercased() == "true" || value == "1": result.append(".*")
                    case "include-other-group":
                        for included in value.components(separatedBy: ",") {
                            result += patterns(in: included.trimmingCharacters(in: .whitespaces), visiting: visiting)
                        }
                    case "policy-regex-filter": filter = value
                    default: break
                    }
                } else if groupNames.contains(field) {
                    // Smart ignores nested groups; include-other-group explicitly
                    // copies their proxy members and is handled above.
                    if entry.kind != .smart { explicit += patterns(in: field, visiting: visiting) }
                } else if !["DIRECT", "REJECT", "REJECT-DROP"].contains(field.uppercased()) {
                    explicit.append("^\(NSRegularExpression.escapedPattern(for: field))$")
                }
            }
            guard let filter, !filter.isEmpty else { return explicit + result }
            return explicit + result.map { pattern in
                pattern == ".*" ? filter : "^(?=[\\s\\S]*(?:\(filter)))(?=[\\s\\S]*(?:\(pattern)))[\\s\\S]*$"
            }
        }
        let groups = groupLines.map { entry -> RuleSchemeGroup in
            var members: [RuleSchemeGroupMember] = []
            var testURLString: String?
            var interval: Int?
            var tolerance: Int?
            let usesInclusion = entry.fields.contains {
                $0.lowercased().hasPrefix("policy-path=") || $0.lowercased().hasPrefix("include-other-group=") || $0.lowercased().hasPrefix("include-all-proxies=")
            }
            if usesInclusion || entry.kind == .smart {
                members = patterns(in: entry.name, visiting: []).map(RuleSchemeGroupMember.nodePattern)
            }
            for field in entry.fields {
                if let separator = field.firstIndex(of: "=") {
                    let key = field[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = field[field.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "url": testURLString = value
                    case "interval": interval = Int(value)
                    case "tolerance": tolerance = Int(value)
                    default: break
                    }
                } else if entry.kind != .smart {
                    if groupNames.contains(field) || ["DIRECT", "REJECT", "REJECT-DROP"].contains(field.uppercased()) {
                        members.append(.reference(field))
                    } else if !usesInclusion {
                        members.append(.nodePattern("^\(NSRegularExpression.escapedPattern(for: field))$"))
                    }
                }
            }
            var parameters = parameterFields(entry.fields)
            if entry.kind == .conditional {
                if let data = try? JSONSerialization.data(withJSONObject: entry.fields), let encoded = String(data: data, encoding: .utf8) { parameters["subnet-fields"] = encoded }
                members = entry.fields.compactMap { field in
                    guard let equal = field.firstIndex(of: "=") else { return nil }
                    let policy = String(field[field.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
                    return .reference(policy)
                }
            }
            return RuleSchemeGroup(name: entry.name, kind: entry.kind, members: members,
                                   testURLString: testURLString, interval: interval, tolerance: tolerance,
                                   algorithm: parameterFields(entry.fields)["algorithm"] ?? (entry.kind == .loadBalance ? (parameterFields(entry.fields)["persistent"] == "true" ? "dest-hash" : "random") : nil),
                                   sourceType: entry.sourceType, sourceFormat: "surge",
                                   parameters: parameters)
        }

        let rulesets = try ruleLines.map { line in
            guard let rule = parseSurgeRuleLine(line) else { throw RuleSchemeParseError.unsupportedSyntax }
            return rule
        }
        guard !rulesets.isEmpty else { throw RuleSchemeParseError.noRulesets }

        return RuleScheme(
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            groups: groups,
            rulesets: rulesets,
            rawConfigurationText: RuleSchemeSourceSanitizer.persistableText(text),
            networkSettings: networkSettings,
            updatedAt: .now,
            isBundled: isBundled
        )
    }

    // MARK: - Network settings

    /// Reads the small cross-client subset Tower can map without guessing.
    /// Surge-style General keys are also accepted in subconverter files, while
    /// Clash DNS lists are translated into the same target-neutral model.
    private func parseNetworkSettings(in text: String) -> RuleSchemeNetworkSettings? {
        let lines = text.components(separatedBy: .newlines)
        var ipv6Enabled: Bool?
        var dnsServers: [String] = []
        var encryptedDNSServers: [String] = []
        var proxyTestURLString: String?
        var inGeneral = false
        var inClashDNS = false
        var clashDNSList: String?

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " }.count
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            if line.hasPrefix("[") {
                inGeneral = line.lowercased() == "[general]"
                inClashDNS = false
                clashDNSList = nil
                continue
            }

            if indent == 0, line == "dns:" {
                inClashDNS = true
                clashDNSList = nil
                continue
            }
            if indent == 0, line.contains(":") {
                inClashDNS = false
                clashDNSList = nil
            }

            if indent == 0, let value = scalar(after: "ipv6:", in: line) {
                ipv6Enabled = parseBool(value)
            } else if inGeneral, let value = assignmentValue(for: "ipv6", in: line) {
                ipv6Enabled = parseBool(value)
            }

            if inGeneral, let value = assignmentValue(for: "dns-server", in: line) {
                dnsServers += commaSeparatedValues(value)
            } else if inGeneral,
                      let value = assignmentValue(for: "encrypted-dns-server", in: line) {
                encryptedDNSServers += commaSeparatedValues(value)
            } else if inGeneral,
                      let value = assignmentValue(for: "proxy-test-url", in: line)
                        ?? assignmentValue(for: "server_check_url", in: line) {
                proxyTestURLString = value
            }

            guard inClashDNS else { continue }
            if indent == 2, line.hasSuffix(":"), !line.hasPrefix("-") {
                clashDNSList = String(line.dropLast()).lowercased()
                continue
            }
            guard indent >= 4, line.hasPrefix("- "), let clashDNSList else { continue }
            let value = unquotedYAMLScalar(String(line.dropFirst(2)))
            switch clashDNSList {
            case "default-nameserver":
                dnsServers.append(value)
            case "nameserver", "fallback":
                if isEncryptedDNS(value) {
                    encryptedDNSServers.append(value)
                } else {
                    dnsServers.append(value)
                }
            default:
                break
            }
        }

        let settings = RuleSchemeNetworkSettings(
            ipv6Enabled: ipv6Enabled,
            dnsServers: unique(dnsServers.compactMap(
                RuleSchemeNetworkSettings.normalizedPlainDNSServer
            )),
            encryptedDNSServers: unique(encryptedDNSServers),
            proxyTestURLString: proxyTestURLString
        )
        return settings.isEmpty ? nil : settings
    }

    private func assignmentValue(for key: String, in line: String) -> String? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let candidate = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        guard candidate == key else { return nil }
        return line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
    }

    private func scalar(after key: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(key.lowercased()) else { return nil }
        return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
    }

    private func commaSeparatedValues(_ value: String) -> [String] {
        value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1": true
        case "false", "no", "0": false
        default: nil
        }
    }

    private func isEncryptedDNS(_ value: String) -> Bool {
        ["https://", "tls://", "quic://"].contains { value.lowercased().hasPrefix($0) }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// `名称 = select,成员,…` or `名称 = url-test,成员,…,url=…,interval=…`.
    /// Commas inside quoted regexes or included group lists are not separators.
    private func surgeFields(_ text: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var escaped = false
        for character in text {
            if character == "\"" && !escaped { quoted.toggle() }
            if character == "," && !quoted {
                fields.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else {
                field.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        fields.append(field.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func parseSurgeGroupLine(
        _ line: String
    ) -> (name: String, kind: RuleSchemeGroup.Kind, fields: [String], sourceType: String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let body = String(line[line.index(after: separator)...])
        let parts = surgeFields(body)
        guard !name.isEmpty, let rawKind = parts.first?.lowercased() else { return nil }

        return (name, nativeKind(rawKind), Array(parts.dropFirst()).filter { !$0.isEmpty }, rawKind)
    }

    /// `RULE-SET,<url>,<策略>[,参数]`, `FINAL,<策略>` or an inline rule such as
    /// `DOMAIN,example.com,<策略>`.
    private func parseSurgeRuleLine(_ line: String) -> RuleSchemeRuleset? {
        let parts = surgeFields(line).map(unquotedYAMLScalar)
        guard parts.count >= 2 else { return nil }
        let type = parts[0].uppercased()

        // Logical rules nest comma-separated conditions inside parentheses, so
        // they cannot be split this way and have no equivalent outside Surge.
        guard !["AND", "OR", "NOT"].contains(type) else { return nil }

        if type == "FINAL" {
            return RuleSchemeRuleset(groupName: parts[1], resource: .inline("FINAL"))
        }

        if type == "DOMAIN-SET", parts.count >= 3 {
            return RuleSchemeRuleset(groupName: parts[2], resource: .inline(parts.prefix(2).joined(separator: ",")))
        }

        if type == "RULE-SET" {
            guard parts.count >= 3,
                  let url = URL(string: parts[1]),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return RuleSchemeRuleset(groupName: parts[2], resource: .remote(url))
        }

        // Everything else ends with the policy, optionally followed by flags
        // such as no-resolve which belong to the rule rather than the policy.
        var fields = parts
        var trailing: [String] = []
        while let last = fields.last,
              last.lowercased() == "no-resolve" || last.contains("=") {
            trailing.insert(last, at: 0)
            fields.removeLast()
        }
        guard fields.count >= 2 else { return nil }

        let policy = fields.removeLast()
        let rule = (fields + trailing.filter { $0.lowercased() == "no-resolve" })
            .joined(separator: ",")
        return RuleSchemeRuleset(groupName: policy, resource: .inline(rule))
    }

    /// Splits on the first comma only: an inline rule such as `[]GEOIP,CN`
    /// contains commas of its own.
    private func parseRuleset(_ value: String) -> RuleSchemeRuleset? {
        guard let separator = value.firstIndex(of: ",") else { return nil }
        let groupName = String(value[..<separator]).trimmingCharacters(in: .whitespaces)
        let target = String(value[value.index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        guard !groupName.isEmpty, !target.isEmpty else { return nil }

        if target.hasPrefix("[]") {
            let rule = String(target.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty else { return nil }
            return RuleSchemeRuleset(groupName: groupName, resource: .inline(rule))
        }

        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return RuleSchemeRuleset(groupName: groupName, resource: .remote(url))
    }

    private func parseGroup(_ value: String) -> RuleSchemeGroup? {
        let fields = value.components(separatedBy: "`")
        guard fields.count >= 2 else { return nil }

        let name = fields[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let sourceType = fields[1].trimmingCharacters(in: .whitespaces).lowercased()
        let kind = nativeKind(sourceType)

        var members: [RuleSchemeGroupMember] = []
        var testURLString: String?
        var interval: Int?
        var tolerance: Int?

        for field in fields.dropFirst(2) {
            let entry = field.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }

            if entry.hasPrefix("[]") {
                let reference = String(entry.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !reference.isEmpty { members.append(.reference(reference)) }
            } else if entry.lowercased().hasPrefix("http://") || entry.lowercased().hasPrefix("https://") {
                testURLString = entry
            } else if isTimingField(entry) {
                let numbers = entry.components(separatedBy: ",")
                interval = numbers.first.flatMap { Int($0) }
                if numbers.count >= 3 { tolerance = Int(numbers[2]) }
            } else {
                members.append(.nodePattern(entry))
            }
        }

        return RuleSchemeGroup(
            name: name,
            kind: kind,
            members: members,
            testURLString: testURLString,
            interval: interval,
            tolerance: tolerance,
            sourceType: sourceType, sourceFormat: "subconverter",
            parameters: ["raw-fields": fields.dropFirst(2).joined(separator: "`")]
        )
    }

    /// The trailing `300,,50` field: only digits and commas, and it must carry
    /// at least one comma so a node pattern of bare digits is not mistaken for
    /// timing information.
    private func isTimingField(_ entry: String) -> Bool {
        entry.contains(",")
            && entry.allSatisfy { $0.isNumber || $0 == "," }
    }
}

/// Structured YAML subset for policy documents. Unsupported tags, aliases and
/// multiline scalars fail explicitly instead of becoming plausible group names.
private struct SchemeYAMLReader {
    private struct Line { var indent: Int; var text: String }
    private var lines: [Line]
    private var index = 0

    init(_ text: String) {
        lines = text.components(separatedBy: .newlines).compactMap { raw in
            let clean = Self.removeComment(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean != "---", clean != "..." else { return nil }
            return Line(indent: raw.prefix { $0 == " " }.count, text: clean)
        }
    }

    mutating func read() throws -> Any {
        guard let first = lines.first else { return [String: Any]() }
        let result = try block(first.indent)
        guard index == lines.count else { throw RuleSchemeParseError.unsupportedSyntax }
        return result
    }

    private mutating func block(_ indent: Int) throws -> Any {
        guard index < lines.count else { return NSNull() }
        if lines[index].text.hasPrefix("- ") || lines[index].text == "-" {
            var array: [Any] = []
            while index < lines.count, lines[index].indent == indent,
                  lines[index].text.hasPrefix("- ") || lines[index].text == "-" {
                let remainder = String(lines[index].text.dropFirst()).trimmingCharacters(in: .whitespaces)
                index += 1
                if remainder.isEmpty {
                    guard index < lines.count, lines[index].indent > indent else { throw RuleSchemeParseError.unsupportedSyntax }
                    array.append(try block(lines[index].indent))
                } else if let pair = Self.pair(remainder), !remainder.hasPrefix("{") {
                    // The first mapping key is on the sequence marker's line.
                    var map: [String: Any] = [:]
                    let mapIndent = indent + 2
                    map[try key(pair.0)] = try valueOrChild(pair.1, parentIndent: mapIndent)
                    if index < lines.count, lines[index].indent > indent {
                        guard let continuation = try block(lines[index].indent) as? [String: Any] else { throw RuleSchemeParseError.unsupportedSyntax }
                        for (key, value) in continuation {
                            guard map[key] == nil else { throw RuleSchemeParseError.unsupportedSyntax }
                            map[key] = value
                        }
                    }
                    array.append(map)
                } else {
                    array.append(try scalar(remainder))
                }
            }
            return array
        }
        var map: [String: Any] = [:]
        while index < lines.count, lines[index].indent == indent {
            guard let pair = Self.pair(lines[index].text) else { throw RuleSchemeParseError.unsupportedSyntax }
            index += 1
            let name = try key(pair.0)
            guard map[name] == nil else { throw RuleSchemeParseError.unsupportedSyntax }
            let priorityOrder = name == "priorities" ? try priorityKeys(pair.1, parentIndent: indent) : nil
            map[name] = try valueOrChild(pair.1, parentIndent: indent)
            if let priorityOrder { map["tower-priority-order"] = priorityOrder }
        }
        return map
    }

    private func priorityKeys(_ text: String, parentIndent: Int) throws -> [String] {
        if text.hasPrefix("{"), text.hasSuffix("}") {
            return try Self.fields(String(text.dropFirst().dropLast())).map { field in
                guard let pair = Self.pair(field, flow: true) else { throw RuleSchemeParseError.unsupportedSyntax }
                return try key(pair.0)
            }
        }
        guard text.isEmpty, index < lines.count, lines[index].indent > parentIndent else { return [] }
        let childIndent = lines[index].indent
        var result: [String] = []
        for line in lines[index...] {
            guard line.indent >= childIndent else { break }
            if line.indent == childIndent, let pair = Self.pair(line.text) { result.append(try key(pair.0)) }
        }
        return result
    }

    private mutating func valueOrChild(_ text: String, parentIndent: Int) throws -> Any {
        if !text.isEmpty { return try scalar(text) }
        if index < lines.count, lines[index].indent > parentIndent ||
            (lines[index].indent == parentIndent && lines[index].text.hasPrefix("- ")) {
            return try block(lines[index].indent)
        }
        return NSNull()
    }

    private func key(_ text: String) throws -> String {
        guard let result = try scalar(text) as? String, result != "<<" else { throw RuleSchemeParseError.unsupportedSyntax }
        return result
    }

    private func scalar(_ raw: String) throws -> Any {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { throw RuleSchemeParseError.unsupportedSyntax }
            return try Self.fields(String(text.dropFirst().dropLast())).map { try scalar($0) }
        }
        if text.hasPrefix("{") {
            guard text.hasSuffix("}") else { throw RuleSchemeParseError.unsupportedSyntax }
            var map: [String: Any] = [:]
            for field in Self.fields(String(text.dropFirst().dropLast())) {
                guard let pair = Self.pair(field, flow: true) else { throw RuleSchemeParseError.unsupportedSyntax }
                let name = try key(pair.0)
                guard map[name] == nil else { throw RuleSchemeParseError.unsupportedSyntax }
                map[name] = try scalar(pair.1)
                if name == "priorities" { map["tower-priority-order"] = try priorityKeys(pair.1, parentIndent: 0) }
            }
            return map
        }
        if text.hasPrefix("\"") {
            guard let data = "[\(text)]".data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [String], let value = array.first else { throw RuleSchemeParseError.unsupportedSyntax }
            return value
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { throw RuleSchemeParseError.unsupportedSyntax }
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        guard !["&", "*", "!", "|", ">"].contains(where: text.hasPrefix) else { throw RuleSchemeParseError.unsupportedSyntax }
        if ["null", "~"].contains(text.lowercased()) { return NSNull() }
        if text == "true" { return true }
        if text == "false" { return false }
        if let number = Int(text) { return number }
        if let number = Double(text), number.isFinite { return number }
        return text
    }

    private static func pair(_ text: String, flow: Bool = false) -> (String, String)? {
        var quote: Character?, depth = 0, escaped = false
        for index in text.indices {
            let character = text[index]
            if let active = quote {
                if character == active && !escaped { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "[" || character == "{" { depth += 1 }
            else if character == "]" || character == "}" { depth -= 1 }
            else if character == ":", depth == 0 {
                let next = text.index(after: index)
                if flow || next == text.endIndex || text[next].isWhitespace {
                    return (String(text[..<index]).trimmingCharacters(in: .whitespaces), String(text[next...]).trimmingCharacters(in: .whitespaces))
                }
            }
            escaped = character == "\\" && !escaped
        }
        return nil
    }

    private static func fields(_ text: String) -> [String] {
        var result: [String] = [], field = "", quote: Character?, depth = 0, escaped = false
        for character in text {
            if let active = quote {
                if character == active && !escaped { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "[" || character == "{" { depth += 1 }
            else if character == "]" || character == "}" { depth -= 1 }
            if character == ",", quote == nil, depth == 0 { result.append(field); field = "" }
            else { field.append(character) }
            escaped = character == "\\" && !escaped
        }
        if !field.trimmingCharacters(in: .whitespaces).isEmpty { result.append(field) }
        return result
    }

    private static func removeComment(_ text: String) -> String {
        var quote: Character?, escaped = false
        for index in text.indices {
            let character = text[index]
            if let active = quote {
                if character == active && !escaped { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "#", index == text.startIndex || text[text.index(before: index)].isWhitespace { return String(text[..<index]) }
            escaped = character == "\\" && !escaped
        }
        return text
    }
}
