import Foundation

/// 节点名称智能清洗与广告过滤工具
/// 用于自动剔除机场节点名称中冗余的营销词、网址、TG群组和无用推广标签
public struct NodeAdSanitizer {
    
    /// 常见机场广告正则匹配模式
    private static let adPatterns: [String] = [
        // 各种括号内的推广信息，如 【年付8折】、【官网: xxx】、【禁止BT】、【测速】
        #"【[^】]*(?:折|特惠|优惠|折|活动|官网|网址|通知|防失联|群|公告|测速|倍率|禁止|维护|推荐)[^】]*】"#,
        #"\[[^\]]*(?:折|特惠|优惠|官网|网址|通知|防失联|群|公告|测速|禁止|维护|推荐)[^\]]*\]"#,
        #"\([^\)]*(?:折|特惠|优惠|官网|网址|通知|防失联|群|公告|测速|禁止|维护|推荐)[^\)]*\)"#,
        #"『[^』]*(?:折|特惠|优惠|官网|网址|通知|防失联|群|公告|测速|禁止|维护|推荐)[^』]*』"#,
        // 推广网址与 Telegram 频道
        #"(?:https?://|www\.)[a-zA-Z0-9\.\-\/]+"#,
        #"(?:tg|t\.me|telegram)[/:@][a-zA-Z0-9_\-]+"#,
        // 常见营销词前缀
        #"^(?:剩余流量|套餐到期|距离重置|过期时间|已用流量|下次重置)[^·\-_\|]*[·\-_\|]?"#
    ]
    
    /// 预编译正则
    private static let compiledRegexes: [NSRegularExpression] = {
        adPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()
    
    /// 清洗节点名称：去除广告、修整多余空格与标点
    public static func sanitize(_ rawName: String) -> String {
        var result = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        
        for regex in compiledRegexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // 清理由于删除广告导致孤立的首尾标点符号，如 "- 香港 01", "| 日本"
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " -_·|[]【】()（）"))
        
        // 压缩连续空格
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return result.isEmpty ? rawName.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }
    
    /// 提取节点中的倍率信息，如 "[1.5x]" -> 1.5
    public static func extractMultiplier(from name: String) -> Double? {
        let pattern = #"(?:x|X|\*)\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:x|X|倍)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(name.startIndex..., in: name)
        guard let match = regex.firstMatch(in: name, options: [], range: range) else { return nil }
        
        for index in 1...2 {
            if index < match.numberOfRanges {
                let rangeAtIndex = match.range(at: index)
                if rangeAtIndex.location != NSNotFound,
                   let swiftRange = Range(rangeAtIndex, in: name),
                   let val = Double(name[swiftRange]) {
                    return val
                }
            }
        }
        return nil
    }
    
    /// 检查节点是否为过高倍率（如超出用户设定阈值）
    public static func exceedsMultiplier(_ name: String, threshold: Double) -> Bool {
        guard let multiplier = extractMultiplier(from: name) else { return false }
        return multiplier > threshold
    }
}
