# 当前交接

更新：2026-09-06。产品约束以 [CLAUDE.md](../CLAUDE.md) 为准；本文只记录当前状态，不再叠加历史开发日志。

## 版本与工作区

- **1.0.7 (43)** 已于 2026-09-06 在远程 Mac mini M2 使用正式版 Xcode 26.6 完成归档和上传，发布提交 `56d2fc9`，脚本退出码 0；归档版本已核对。Apple 已处理完成；外部审核提交返回 HTTP 422 / `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING`，已联系 Apple 支持，外部测试尚未恢复。
- build 43 修复 Self-Configuration 下载后缺少刷新按钮的问题；更新内置 ACL4SSR 至 `f7c4233b2bc706c89668753b18a9f899d7e9f9bf`，77 个 MRS/SRS 产物已回读校验。测试 937 通过、1 跳过、0 失败；本机未连接可用 iPhone，尚未真机安装。
- 1.0.6 (43) 上传被 Apple 以预发布通道关闭拒绝，改用 1.0.7 (43)。旧构建当前显示已失效，原因尚未确认。对外更新日志：修复一些bug。

- **1.0.6 (42)** 已于 2026-09-05 在家中 Mac mini M2 使用正式版 Xcode 26.6 完成 Release 归档并上传 App Store Connect，发布提交 `37c07ce`。归档、上传均成功，脚本退出码为 0；归档版本、Bundle ID、签名及团队匹配已核验。
- App Store Connect 已完成 build 42 的处理并批准外部测试；已关联现有内部和外部测试群组，外部群组显示「正在测试」，中文测试说明已保存。
- build 42 简化设置入口，拆分 iCloud 与重置；新执行的规则排序同时更新编辑文本和导出优先级，旧快照的纯展示排序不会自动改变路由，FINAL 始终最后。
- build 42 修复 sing-box 的 YAML null、WireGuard endpoint、Snell v5 映射及 TLS SOCKS 跳过；规则下载显式使用独立 DNS 解析；sing-box / Hiddify 保留方案 DNS、端口和 IPv6 设置。已有客户端配置需要重新导出。
- build 41 引入的 Clash Mi / Karing、客户端筛选与局域网统一排序、代理集合继续保留；客户端选择不再强制居中，边缘卡片以短动画最小滚动至完整可见。
- 内置 ACL4SSR 仍为上游最新提交 `864e3f3856347f67f4125505365295a7cc0490e7`，MRS/SRS 固定到不可变产物提交。
- build 42 发布验证：TowerTests 936 通过、0 失败、1 跳过；12 个客户端生成回归、180 次 sing-box 内核检查、独立冷启动/缓存/失败重试测试通过；77 个远程规则产物全量回读通过。本机以全新目录签名构建，已核对手机安装记录为 1.0.6 (42) 并成功启动。

## 当前未发布改动

- 修复 Shadowrocket 实际 YAML 导出遗漏 AnyTLS/SOCKS5/HTTP Reality、SS 原生 TLS，以及 SOCKS5/HTTP SNI/ALPN/证书验证参数。旧代码回归18断言失败；全量968项XCTest（2跳过、0失败）和39项Swift Testing通过。实体iPhone已覆盖安装，命令启动被拒绝，待手动确认。协议实验覆盖13种协议、25个组合，关键4条实际导出参数外网请求通过；完整客户端验收另记本地报告。

- 补修 Clash VMess HTTP 数组 Host/path 原样输出的问题。真实旧配置字段连接失败，新生成字段连接通过；966 项 XCTest（1 跳过、0 失败）和 39 项 Swift Testing 通过。此补丁安装时未发现唯一可用实体 iPhone，最新补丁尚未覆盖安装。

- QuanX 官方 News 对照修复：补 SOCKS5 TLS、HTTP SNI、ALPN 与各 TLS 协议 Reality 字段；支持 VMess 明文 HTTP；补 ip-asn/host-wildcard 规则导入。全量 964 项 XCTest（1 跳过、0 失败）和 39 项 Swift Testing 通过；实体 iPhone 已覆盖安装并成功启动。另有 11 节点真实服务端测试通过独立内核外网请求，QuanX 加载与连接待用户测试。

- 修复 Quantumult X 本地地区延迟组只写 server-tag-regex、实际未载入的问题：导入方案和内置预设均明确列出过滤后的节点 tag，不额外包含 direct。远程代理集合仍保留资源筛选。

- 策略兼容改为导出时降级：不支持的 fallback / load-balance 转延迟优选；条件组转同名手动组并保留默认策略（无默认时保留候选）；relay / 未知类型转手动选择；不支持的附加参数忽略并提示。原始方案不改写，原生能力优先。类型或参数不兼容不再阻止导出；循环、重复名称和缺失引用仍做有效性校验。

- 修复 Loon 导入 Surge `DOMAIN-SET` 语法错误：旧方案中的域名列表也参与下载，非 Surge 目标展开为 DOMAIN / DOMAIN-SUFFIX；缺少缓存时提示刷新，避免漏规则。Surge 优先规则集模式保留原生引用。已有方案需主动刷新一次，再重新导出。回归：957 个 XCTest（1 跳过，0 失败）及 39 个 Swift Testing 测试通过。

- 支持导入 Surge Smart 组及 `include-other-group` / `include-all-proxies` / `policy-path` 节点池和正则筛选；规则模板的外部节点地址不主动获取，节点继续由塔台中选择的订阅提供。Surge / Egern 保留各自原生 `smart`；其他配置客户端将 Smart 降级为延迟优选并合并提示，保存的原方案不变。不支持的 `no-alert` 通知参数忽略并提示，不阻止导出。
- Smart 没有匹配节点时保留同名拒绝策略并提示；不存在的策略引用阻止导出。修复 `DOMAIN-SET` 的 `extended-matching` 被误识别为策略名。Smart 在策略编辑、持久化及规范文本中保留类型。
- 更正此前安装记录：Xcode 27 的 CoreDevice 列表含模拟器，旧脚本误选模拟器并安装了旧产物，先前“真机已安装修复版”的结论不成立。已增加实体设备交叉校验，强制 iOS 真机目标和 SDK；实体 iPhone 已重新覆盖安装并通过命令成功启动，设备安装记录复核为 1.0.7 (43)；实际 Surge 导出仍待用户确认。
- 验证：942 个测试通过、1 跳过、0 失败；本地化提取检查通过。已用反馈中的 Surge-Mac 模板生成配置并通过 Surge 官方 CLI `--check`（OK）。含保存原文的旧 Surge 方案在加载时自动恢复被旧解析器丢弃的 Smart 图，保留方案标识、元数据和独立自定义覆盖；“刷新”仍只更新规则列表。未保存原文的旧方案需要重新导入。

- 策略兼容性扩展：新增 fallback、带算法的 loadBalance、网络条件、独立代理链及未知类型；原生 QX / Egern / sing-box 方案导入与结构化 YAML 解析，保留来源、参数及规范文本元数据。旧方案从保留原文恢复丢失的策略语义，用户覆盖保持独立。
- 导出前校验重复名称、未知引用、循环、无效表达式及空组；空组以同名拒绝策略保留并提示。QX 资源标签、Clash provider、Egern 来源通过 URL 哈希匹配已启用订阅，本地与代理集合均限制到匹配来源，不自动获取新订阅。
- 同格式支持 Surge / QX / Egern 网络条件，以及 Loon 独立代理链；无法表达的跨格式规则、类型和参数明确拒绝。YAML anchors/tags 等未实现语法明确报错；不声称支持任意配置全文。

- 本轮验收：988 项通过（含 1 项本地真实模板审计）、1 跳过、0 失败；本地化 759 项提取检查通过。实际生成的 Mihomo fallback/轮询/哈希配置通过检查器与隔离运行；反馈 Surge 模板通过官方 CLI。实体 iPhone 已覆盖安装并成功启动 1.0.7 (43)。其他客户端逐项界面实测仍未全部完成，不等同于全平台实机验收。

## 功能边界

- 轻点客户端切换；直接横滑浏览；长按卡片后拖动排序。筛选页右侧手柄直接拖动。两个入口共用持久化顺序，局域网是导出入口而非新的配置格式。
- 勾选订阅或自有节点不改变首页排序。刷新迁移节点排除状态，旧请求不得覆盖新编辑或已删除来源。
- 代理集合默认关闭：支持的完整配置直接引用原始订阅 URL，由客户端更新远端节点。协议筛选和本地节点统计不代表远端实际内容。
- 代理集合支持 Stash、Clash、Clash Mi、Karing、Surge、Loon、QuanX、Egern；Shadowrocket、Hiddify、V2Box、sing-box MT 保留本地展开。不要把社区 sing-box fork 的 provider 扩展视为所有客户端支持。
- 原始链接可能含凭据；只在用户主动开启时写出。iCloud 同步也须单独授权，默认关闭。
- 一键导入的本机服务仅绑定 127.0.0.1，45 秒失效；局域网共享是独立、用户主动开启的前台服务。二者不能混为长期后台订阅托管。
- 地图继续使用名称优先的离线识别和自绘 `WorldDotMapView`，不改用 MapKit 或联网定位。
- 同链接重新导入后的覆盖/重名行为由目标客户端决定；代理集合能减少节点更新后的重复导入，但塔台规则或自有节点变化仍需重新导出。

## 从哪里继续

换机后在干净工作区的 `main` 分支执行 `git pull --ff-only origin main`，再按该机器的 [AGENTS](../AGENTS.md) 设置 Xcode。先读本文及审查报告，未完成项见 TODO；不要依赖上一台机器的 DerivedData、签名资产或临时测试文件。

| 内容 | 唯一维护入口 |
| --- | --- |
| 产品能力与用户说明 | [README](../README.md)、[支持页](support.md) |
| 不可破坏的约束 | [CLAUDE](../CLAUDE.md) |
| 机器与工具链 | [AGENTS](../AGENTS.md) |
| 构建、测试、安装、真机清单 | [DEVELOPMENT](DEVELOPMENT.md) |
| 模块、数据流、资源边界 | [ARCHITECTURE](ARCHITECTURE.md) |
| 规则产物与 TestFlight 发布 | [RELEASING](RELEASING.md) |
| 未完成需求、待用户样本 | [TODO](TODO.md) |
| 本轮审查及验证 | [项目审查](../plans/2026-09-05-project-audit.md) |
| 上架成稿 / 隐私政策 | [APP-STORE](APP-STORE.md)、[privacy](privacy.md) |

旧过程记录留在 Git 历史，不再作为当前验收依据。公开文档不得记录设备标识、签名团队、描述文件 UUID、个人邮箱或凭据。


### 2026-09-06 Egern / Snell / QuanX MUX 修复

- 修复 Egern VLESS Vision 与 TLS/Reality 层级、Trojan WS、证书验证默认值及部分 TLS/协议参数；普通 SS-over-TLS 不再静默降成 SS。
- Mihomo 目标允许 Snell v4/v5，Loon 允许 Trojan HTTP。Stash 的 v4/v5 需要 iOS 3.6+；未提供客户端版本选择时按 v1–v3 兼容基线导出，其他版本跳过并计数，避免旧版整份配置加载失败。原节点版本不改写。 本次回归 1010 项通过、3 项跳过、0 失败；后续已覆盖安装并启动，最新 Stash 验证与暂缓决定见下文。
- ProxyNode 新增可选 pluginMux，YAML/URI 解析和分享/插件导出保留；QuanX 的 v2ray-plugin 仅明确无 MUX 时放行，旧订阅需刷新以取得该参数。
- 全量验证：972 XCTest（3 跳过、0 失败）及 39 Swift Testing 通过。客户端运行时复测与真机安装/启动是独立验收步骤。


### Karing 参数保留补修

Karing YAML 不再丢失 AnyTLS / SOCKS / HTTP 的 Reality 以及原生 SS TLS 参数。新增生成与解析回读回归，973 XCTest（3 跳过、0 失败）和 39 Swift Testing 通过。目标客户端能否握手仍以实机复测为准；Karing Trojan Reality、WireGuard 的既有失败未在本次确认根因。

### Stash 实机反馈兼容补修

- 当前导出策略只保留 VLESS TCP Reality；AnyTLS / Trojan / SOCKS / HTTP Reality、原生 SS-over-TLS 与 XHTTP 暂时跳过并计数，不静默改成普通 TLS/TCP。这里记录的是保守导出策略，不代表这些组合均已证实被 Stash 禁止。SS 的 v2ray-plugin 保持支持。
- Stash Trojan 使用官方 `sni` 字段。用户已确认测试节点 23（Trojan WS TLS）可连接；不将先前超时归因为 SNI。独立 Mihomo 对原字段和修正字段均返回 HTTP 204，不能代替 Stash 验收。
- 回归 1012 项通过、3 项跳过、0 失败。其余 6 个反馈节点的处理是兼容性跳过，不是恢复该协议连接。

### Stash 3.4：暂缓扩展，等待后续版本（2026-09-06）

- 用户确认当前使用的 Stash 为 3.4，并反馈这是目前可获取的最新版本；决定先记录，暂缓进一步调整。维持现有导出策略，不主动升级客户端或继续试改 Reality 参数。
- 官方协议文档列出的 Snell v4/v5、Trojan Reality、VLESS XHTTP 要求 iOS 3.6+。文档出现新能力不代表用户已能安装对应版本；恢复这些导出前须核对实际客户端版本并实机验证。
- AnyTLS Reality、SOCKS5 Reality、HTTP Reality：已确认塔台旧导出遗漏 Reality 参数，但 Stash 对这些协议组合的支持尚未验证。不能把“生成器漏字段”当作“客户端不支持”的证据；若后续确认支持，应补齐公钥、short-id 等参数并实测，而非永久跳过。仅补字段或其他内核连接成功也不等于 Stash 支持。
- 原生 SS-over-TLS 同样保持暂时跳过，支持能力待独立核对；不要与已可用的 SS WebSocket TLS 插件混淆。
- 测试节点当前跳过：07 AnyTLS Reality、08 Trojan Reality、09 SOCKS5 Reality、10 HTTP Reality、11 SS TLS、16 Snell v4、22 VLESS XHTTP TLS。05 VLESS Reality 与 23 Trojan WS TLS 已获用户客户端成功反馈；23 的先前超时根因未确认。
- 最新修复版塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动；1012 项通过、3 项跳过、0 失败。跳过节点不代表协议连接已修复。
- 后续工作入口见 [TODO](TODO.md#stash-34兼容性暂缓)。依据：[Stash 官方协议文档](https://stash.wiki/proxy-protocols/proxy-types)。

### sing-box SS WebSocket 导入修复（2026-09-06）

- 实机报 `outbounds[30].transport: json: unknown field "transport"`，对应测试节点 25（SS WebSocket TLS）。生成器已写 SIP003 `plugin` / `plugin_opts`，又错误添加顶层 V2Ray `transport`。
- 顶层 `transport` 限定为 VMess / VLESS / Trojan；SS 的 WebSocket、TLS、Host、path、MUX 继续保留在插件配置内，不跳过节点。覆盖 sing-box 与 Hiddify 生成回归。
- sing-box 1.14.0 对用户原文件复现报错；只删除多余字段后完整配置通过 `check`，该节点独立运行并访问外网返回 HTTP 204。全量测试 1013 项通过、3 项跳过、0 失败；不等同所有节点连接验收。

### sing-box 原生 SS TLS 过滤修复（2026-09-06）

- 用户反馈测试节点 11 无法连接。原生 SS-over-TLS 被旧生成器静默输出为普通 Shadowsocks，TLS 语义丢失。
- 已核对官方 Shadowsocks schema，并用 sing-box 1.14.0 对添加 `tls` 的节点执行 `check`，确认返回 `unknown field "tls"`；这与 SIP003 插件 TLS 不同。
- sing-box / Hiddify 对没有插件承载的原生 SS TLS 跳过并计数，不改写源节点；普通 SS、v2ray-plugin WebSocket TLS 及其他客户端已有输出保持。回归同时检查跳过计数、策略组引用清理及插件参数保留。
- 验证：1014 项通过、3 项跳过、0 失败；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动。处理结果是明确跳过不兼容节点，不是恢复原生 SS TLS 连接。

### Loon Reality 实机反馈（2026-09-06）

- 用户导入补参数诊断配置后，07 AnyTLS Reality 显示 70 ms、08 Trojan Reality 显示 72 ms，客户端分别识别为 anytls+reality / trojan+reality。确认旧生成器漏字段，不能归因为客户端不支持。
- 已将这两个协议的 `public-key`、`short-id`、`sni` 写入 Loon 导出，原节点保留。普通 AnyTLS / Trojan 输出不受影响。
- 01 SOCKS5 TLS、02 HTTPS、09 SOCKS5 Reality、10 HTTP Reality、11 原生 SS TLS、13 Hysteria2 在诊断配置中仍失败或超时。09 缺原始 Reality 公钥，此轮诊断未补齐；其失败不是客户端不支持的证据。其他未确认字段调整尚未合入生成器，未新增跳过策略。
- 02 的独立 sing-box 请求返回 HTTP 204；13 独立请求曾连接重置，重试返回 204。其他内核结果不代替 Loon 实测，需客户端版本和失败日志继续定位。

### Loon 3.5.0 用户名与 SOCKS5 TLS 修复（2026-09-06）

- 原日志显示 01 的 SOCKS5 认证失败。对照文件仅去掉 01/02/09/10 的简单用户名引号，用户反馈 01 恢复为 133 ms、02 恢复为 122 ms；源用户名和密码与 YAML 一致。
- 生成器对安全的简单用户名不加引号，密码仍按 Loon 格式加引号；含逗号等特殊字符的用户名维持转义。SOCKS5 TLS 写入已参与成功实测的 `over-tls`、`sni`、`alpn`；HTTPS 保留 `sni`、`alpn`。
- 09、10、11、13 仍未成功；13 日志为 `ERR_HANDSHAKE_TIMEOUT`，UDP 发出 10 个包、收到 0 个，尚未确认网络/服务端/客户端原因。不新增跳过策略，不把它们记录为已修复。
- 验证：1016 项通过、3 项跳过、0 失败；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并成功启动。

- Loon 后续状态：用户要求先记录、暂停排查，转查 Surge；剩余 09/10/11/13 不新增跳过，详见 TODO。

### Surge 实测与 Mac 版本边界（2026-09-06）

- 用户设备为 Surge iOS 5.21.1 (3810)。13 Hysteria2 / 14 TUIC v5 在原网络失败，关闭 ECN 对照仍失败；换网络后用户确认两者恢复。原网络相关因素待确认，不能推断为协议不支持。成功时沿用 ECN 关闭对照，尚未单独验证 ECN 默认值。
- 11 原生 SS-over-TLS：原导出遗漏 TLS 层。仅为该节点添加 `tls=true` 与 `sni` 的诊断配置通过 Mac 检查器，但用户手机仍失败。没有证据证明 Surge 已按该字段启用原生 SS TLS；不把参数被接受等同于协议生效，也不把失败直接写成所有版本均不支持。
- 本机实际安装 Surge Mac 6.4.4 (10661)，明显早于用户粘贴日志中的 6.7.0 / 6.8.0；未升级、未切换电脑正在使用的配置。此前 `surge-cli --check` 只证明旧版本接受配置，不是新版/手机的连接验收。
- 用户提供更新日志：6.7.0 提到 TLS 代理 ALPN 自定义；6.8.0 提到独立证书校验名称、ECN 自动回退、TLS 1.3 可靠性及 Hysteria/TUIC 分片握手响应修复。日志开头另列 MASQUE、HTTP/2 CONNECT UDP、TrustTunnel HTTP/3 和 `http probe` 等，但开头未提供版本标题，不能直接归到某版本。
- 该更新日志未明确声明新增原生 Shadowsocks-over-TLS。TLS/ShadowTLS/其他协议的修复不是 SS 原生 TLS 支持的证据。11 暂保留待研究；未将本轮 Surge 诊断参数写入塔台生成器。

### Hiddify SOCKS TLS 导入修复（2026-09-06）

- 用户 Hiddify 4.0.0 dev 报 `outbounds[11].tls: json: unknown field "tls"`。该出站为 01 SOCKS5 TLS；09 SOCKS5 Reality 同样带有非法 TLS 字段。
- 旧代码仅对官方 sing-box 做 SOCKS TLS 过滤，遗漏 Hiddify。现在两目标都对 SOCKS TLS / Reality 跳过并计数，生成策略组时同步移除引用；普通 SOCKS5 与 HTTPS 保留，不把 TLS 静默改成明文。
- 已生成用户样本的修复副本，移除两个不兼容出站，JSON 与策略组引用检查通过；完整 Hiddify 导入和其他协议运行仍需客户端验证，不以官方 sing-box 内核替代 Hiddify fork 验收。

### V2Box 实机反馈待验证（2026-09-06）

- 截图中 03 Trojan TLS、08 Trojan Reality、24 SS TCP 有延迟；04 VMess HTTP、11 原生 SS TLS 超时。02 HTTPS、10 HTTP Reality 显示为订阅卡片，疑似 HTTP URI 被识别为订阅地址，不能据此认定协议不支持。
- 代码检查：VMess 分享器直接输出 `net=http,type=none`；v2rayN 分享格式用 `net=tcp,type=http` 表达 TCP HTTP 伪装。已依据本地测试样本生成 04 对照链接，尚待 V2Box 实机验证；不得把 HTTP/2 与 TCP HTTP 伪装混为一谈。
- SS 分享器未编码无插件的原生 TLS，11 被输出为普通 SS；V2Box 可接受的原生 TLS 表达方式仍待确认，不记录为已修复。
- 本轮未修改生成器，也未安装新构建。参考：https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link 。

### Clash Mi 实机反馈（2026-09-06）

- 用户截图：07 AnyTLS Reality、09 SOCKS5 Reality、10 HTTP Reality、11 原生 SS TLS 未显示延迟，仅显示闪电图标；05 VLESS Reality、08 Trojan Reality、12 Hysteria、13 Hysteria2、14 TUIC 有延迟。闪电图标本身不是具体错误日志。
- 当前 Clash Mi 导出路径未给 07/09/10 输出 Reality 参数，11 未输出原生 TLS，存在语义丢失。尚未取得本次实际 YAML 和 Clash Mi 内核版本，不能把代码检查当作用户文件逐项验证。
- Mihomo 官方 AnyTLS 文档明确不支持 AnyTLS+Reality；此项不能通过仅添加 reality-opts 解决。09/10/11 仍需结合具体内核字段与实际配置确认，不笼统推断所有 Reality 不支持。来源：https://wiki.metacubex.one/config/proxies/anytls/ 。
- 本轮仅记录诊断，未修改导出过滤或生成器。

### Clash / Hako 本地内核复现（2026-09-06）

- 官网 clash.md 指向 TokenPLS/Hako，独立于直接运行 Mihomo。本轮从官方仓库编译 CLI，固定提交 `e6ac1ee1f6cdff5aa61f7dd0e8a3fd735a56c97d`；不代表已确认手机安装版本对应此提交。
- 使用此前用户提供测试节点参数，逐节点运行独立内核，仅监听本机回环随机端口，以 HTTPS generate_204 请求验证；没有切换系统代理或修改服务器。并非本次手机导出 YAML 的逐字复现。
- 对照 08 Trojan Reality、24 SS TCP 均返回 HTTP 204。07 AnyTLS Reality、09 SOCKS5 Reality、10 HTTP Reality 均 curl 35 / HTTP 000，11 原生 SS TLS curl 28 / HTTP 000。
- 为 07/10 补入用户 JSON 中的真实 Reality 公钥、short ID 与 chrome 指纹，仍 curl 35；为 11 补 tls、sni、servername 后仍超时。全部配置检查返回 0，说明检查通过并不保证字段生效。
- 源码：AnyTLSOption、HttpOption、Socks5Option 以及各自握手路径没有 Reality 接入；ShadowSocksOption 没有顶层原生 TLS 字段，插件 TLS 与其不同。因此在该提交上不能靠补上述字段恢复这些原生组合。09 的现有源文件没有真实 Reality 公钥，本轮没有伪造或复用其他节点公钥做补参数对照。
- 生成器仍存在把这些组合静默导出为普通 TLS / SS 的问题，本轮未修改生产代码或安装新构建。源码依据：https://github.com/TokenPLS/Hako/tree/e6ac1ee1f6cdff5aa61f7dd0e8a3fd735a56c97d/adapter/outbound 。

### Clash / Hako 导出修正（2026-09-06）

- `.clashApple` 对 AnyTLS/SOCKS5/HTTP Reality 及无插件的原生 SS TLS 跳过并计数，避免降级成普通 TLS 或明文 SS。源节点不变，组成员按同一过滤结果生成。
- 普通协议、Trojan/VLESS Reality 以及 SIP003 WebSocket TLS 保留；本轮不扩展到尚未做对应内核验证的其他客户端。
- 新增回归在旧实现上失败，验证跳过数量、组引用清理和受支持组合保留；修复后执行全量测试与真机安装。
- 验证结果：1018 项通过、0 失败、3 跳过；真机构建已完成。安装步骤失败后重新枚举未找到唯一可用实体 iPhone，因此本轮尚未安装或启动新版，需重新连接设备后继续。

### Hiddify WireGuard 字段修正（2026-09-07）

- 用户重开 Hiddify 后，本地连接错误消失，转为 `outbounds[22].address: unknown field`，对应 15 WireGuard。
- 旧式 WireGuard outbound 必须使用 `local_address`，之前误用了新版 endpoint 的 `address`。修正共享旧式出站生成路径并补 IPv4 /32、IPv6 /128 缺省前缀；sing-box 新版 endpoint 保持 address。保留节点及凭据，不新增跳过。
- 用户样本已生成本地修复副本；回归测试在旧实现上失败，覆盖旧式字段、地址前缀与新版 endpoint 区分。尚待 Hiddify 手机实际导入和流量确认。
- 验证完成：1018 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动，包含此前 Clash/Hako 过滤修正。Hiddify 本次导入仍待用户验证。

### Hiddify SSR 实机不支持（2026-09-07）

- WireGuard 字段修正后用户进入代理页，17 SSR 明确返回 `ShadowsocksR is deprecated and removed in sing-box 1.6.0`；65535 ms 是失败显示，不是有效延迟。
- Hiddify 能解析配置不代表其运行内核支持 SSR。修正目标支持列表排除 SSR，源节点保留，导出跳过并计数，策略组同步清理；其他客户端不变。
- 回归验证目标能力声明、跳过计数与无悬空引用，旧实现已复现失败；生成本地兼容副本继续保留 WireGuard 修正。
- 验证：1019 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动。需重新导出替换 Hiddify 已有配置，旧配置不会自动移除 SSR。

### Issue #20 粘贴协议入口统一（2026-09-07）

- https://github.com/pengchujin/tower/issues/20 反馈 wireguard://、wg:// 在底层能解析但粘贴入口不识别。本地回归确认旧入口返回 unknown。
- SourceInputDetector 移除重复协议白名单，非 HTTP(S) 单节点统一使用 SubscriptionParser.parseURI；HTTP(S) 保留订阅与节点的歧义判定。Snell 代理行仍交给同一解析器识别。
- 新增全部 ProxyKind 的规范分享链接识别、WireGuard 两种 scheme、空白、多行节点、hy/hy2/socks 别名与无效 URI 回归；使用合成凭据，不写入此前测试服务器秘密。全量测试包含之前协议导入导出回归，不能等同真实剪贴板 UI 或网络连通验收。
- 额外边界修正：WireGuard URI 拒绝空主机（例如只有 wg://）；多行测试使用不同端点，避免正常去重影响计数。
- 最终验证：1020 项通过、0 失败、3 跳过；塔台 1.0.7 (43) 已覆盖安装到实体 iPhone 并启动。已从此前节点 15 生成本地 wireguard/wg 两份测试链接，实际系统剪贴板交互待用户验证；未在 GitHub 评论或关闭 issue。

### 1.0.7 (44) 发布准备（2026-09-07）

- 整合上述策略组、客户端兼容性及粘贴识别修正。1020 项通过、0 失败、3 跳过；763 条本地化检查通过；规则快照最新，77 个远程规则产物全量校验通过。发布脚本、规则更新器及设备选择脚本测试通过。
- 1.0.7 (44) 已覆盖安装到实体 iPhone 并启动；正式归档上传状态后续记录。更新日志见 RELEASE-NOTES-1.0.7-44.md。
