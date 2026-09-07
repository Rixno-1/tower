# 塔台 1.0.7 (44) 更新日志

- 完善策略组导入、编辑与跨客户端转换，保留受支持的 Smart、故障转移和负载均衡策略；不支持的类型或算法会降级并显示提示。
- 改善策略组引用检查及空组处理，避免导出失效引用或意外直连。
- 修复 WireGuard 分享链接的粘贴识别，支持 wireguard:// 和 wg://，并拒绝空链接。
- 修复 Loon 的 AnyTLS/Trojan Reality、SOCKS TLS 和用户名格式等兼容问题。
- 修复 sing-box/Hiddify 的 Shadowsocks 插件及 WireGuard 导出字段；不支持的协议组合明确跳过并计数。
- 调整 Clash、Stash 的协议兼容处理，避免丢失关键参数后生成无法连接的节点。
- 完善 Egern、Karing 和 Quantumult X 的部分 TLS、Reality、WebSocket 与插件参数保留。
- 改善规则方案导入命名及本地化文案。

更新后请重新导出并替换客户端中的旧配置。部分协议组合仍受目标客户端版本限制；本次更新不代表所有组合均已通过实机连接验证。
