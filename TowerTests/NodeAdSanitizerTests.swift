import XCTest
@testable import Tower

final class NodeAdSanitizerTests: XCTestCase {
    
    func testSanitizesPromotionalBracketsAndTags() {
        let rawNames = [
            "【年付8折】香港 01": "香港 01",
            "香港 02 [官网: proxy.com]": "香港 02",
            "[2.0x] 日本 01 (测速推荐)": "[2.0x] 日本 01",
            "『限时特惠』新加坡 05 - tg:@sample": "新加坡 05",
            "美国 01 - 剩余流量: 50GB": "美国 01"
        ]
        
        for (raw, expected) in rawNames {
            let sanitized = NodeAdSanitizer.sanitize(raw)
            XCTAssertFalse(sanitized.contains("年付8折"), "Should clean promotion")
            XCTAssertFalse(sanitized.contains("官网"), "Should clean website")
            XCTAssertFalse(sanitized.contains("tg:"), "Should clean telegram channel")
            XCTAssertFalse(sanitized.contains("限时特惠"), "Should clean promo keywords")
        }
    }
    
    func testExtractsMultiplier() {
        XCTAssertEqual(NodeAdSanitizer.extractMultiplier(from: "香港 01 [2.5x]"), 2.5)
        XCTAssertEqual(NodeAdSanitizer.extractMultiplier(from: "日本 02 x1.5"), 1.5)
        XCTAssertEqual(NodeAdSanitizer.extractMultiplier(from: "新加坡 3倍"), 3.0)
        XCTAssertNil(NodeAdSanitizer.extractMultiplier(from: "普通节点 01"))
    }
    
    func testDeduplicationByConnection() {
        let node1 = ProxyNode(
            kind: .shadowsocks,
            name: "【8折】香港 01",
            server: "hk.node.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "test-password",
            rawURI: "ss://test1"
        )
        let node2 = ProxyNode(
            kind: .shadowsocks,
            name: "香港 BGP 高速",
            server: "hk.node.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "test-password",
            rawURI: "ss://test2"
        )
        let node3 = ProxyNode(
            kind: .shadowsocks,
            name: "日本 01",
            server: "jp.node.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "test-password",
            rawURI: "ss://test3"
        )
        
        let nodes = [node1, node2, node3]
        let deduplicated = nodes.deduplicatedByConnection()
        XCTAssertEqual(deduplicated.count, 2, "Duplicate HK node with different names should be collapsed")
        XCTAssertEqual(deduplicated[0].name, "【8折】香港 01")
        XCTAssertEqual(deduplicated[1].name, "日本 01")
    }
}
