# AI 对话（AIChat）

一个纯 SwiftUI 的 iOS AI 对话客户端：自己填 API 端点和密钥，支持多会话、图片/文件、深度思考档位与联网搜索。零第三方依赖。

## 页面

| 页面 | 内容 |
|---|---|
| 主页 | 会话列表 → 进入聊天：流式输出、Markdown、图片、文件、联网、思考过程折叠 |
| 插件 | 占位 |
| 设置 | API 地址、密钥、测试连接、模型选择、默认参数 |

标签栏使用 iOS 26 的液态玻璃样式（用 Xcode 26 SDK 编译自动生效）。

## 协议

兼容 OpenAI 协议的服务都能接：`GET /v1/models` 拉模型、`POST /v1/chat/completions` 流式对话。

- **深度思考**：按服务商自动切换字段名（`reasoning_effort` / `thinking` / `enable_thinking`）；模型不认就自动去掉参数重试一次。
- **联网搜索**：本地检索 DuckDuckGo（Bing 兜底），把结果作为上下文注入，任何模型都能用，不需要服务端支持工具调用。
- **图片**：压缩成 JPEG 后按 `image_url` + base64 发送（需模型支持视觉）。
- **文件**：文本类文件直接读取内容注入对话。

## 构建

```
project.yml            # XcodeGen 工程描述
Sources/               # 源码
Resources/             # AppIcon
.github/workflows/     # 云端出无签名 IPA
```

推送到 GitHub 后由 Actions 产出 `AIChat-unsigned.ipa`，自行签名安装。

## 自定义

| 想改什么 | 改哪里 |
|---|---|
| App 名称 / Bundle ID | `project.yml` |
| 最低 iOS 版本 | `project.yml` → `deploymentTarget.iOS` |
| 界面 | `Sources/*.swift` |
| 联网检索源 | `Sources/SearchService.swift` |

## 已知限制

- 产物为 ad-hoc 签名，必须重签后安装
- 免费 Apple ID 签名 7 天过期
- 附件目前只支持图片与文本类文件（PDF/Office 需转文本）
- 联网检索依赖第三方网页解析，结果不保证稳定
