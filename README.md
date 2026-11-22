# TodoApp — iOS IPA 自动打包模板

一个纯 SwiftUI 的待办清单 App（约 300 行，无任何第三方依赖），
配 GitHub Actions，push 后自动产出 **未签名 IPA**，由你在 iPhone 上自行签名安装。

## 目录结构

```
├── project.yml                     # XcodeGen 工程描述（不用手点 Xcode）
├── Sources/
│   ├── TodoApp.swift               # App 入口
│   ├── Models.swift                # 数据模型 + UserDefaults 持久化
│   └── ContentView.swift           # 主界面
├── Resources/
│   └── Assets.xcassets/            # AppIcon（1024 单尺寸）
└── .github/workflows/ios.yml       # 云端构建脚本
```

`TodoApp.xcodeproj` 与 `Info.plist` 由 XcodeGen 自动生成，**不需要提交**。

## 用法（3 分钟出 ipa）

1. 在 GitHub 新建一个仓库（**建议 Public**，Actions 全免费）
2. 把本目录所有文件上传上去（网页拖拽即可，不用装 git）
3. 打开仓库的 **Actions** 标签页 → 等 `Build iOS IPA` 跑完（约 3–5 分钟）
4. 进入那次运行 → 页面底部 **Artifacts** → 下载 `TodoApp-ipa`
5. 解压得到 `TodoApp-unsigned.ipa` → 传到 iPhone → 用你的签名工具签名安装

## 自定义

| 想改什么 | 改哪里 |
|---|---|
| App 显示名称 | `project.yml` → `CFBundleDisplayName` |
| Bundle ID | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` |
| 最低 iOS 版本 | `project.yml` → `deploymentTarget` |
| 界面 | `Sources/ContentView.swift` |

## 已知限制

- 产物为 **ad-hoc 签名**，无法双击安装，必须经签名工具重签
- 免费 Apple ID 签名 7 天过期；$99 开发者账号 1 年
- 未包含 App Store 上架所需的图标变体与隐私清单（上架再补）
