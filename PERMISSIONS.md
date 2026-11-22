# AIChat 2.2 权限与打包说明（TrollStore / no-sandbox / 本机 BusyBox / WQ）

> 仅用于你自己的设备、自己的数据与研究用途。把全盘读写能力交给 LLM 意味着模型能看到你设备上的几乎所有文件，请只接入可信的模型端点（`settings.baseURL` 不要填来历不明的中转），并保持「高危工具二次确认」开启或至少清楚风险。

## 一、2.2 改了什么

| 文件 | 改动 |
|---|---|
| `Sources/LocalShell.swift`（新增） | `posix_spawn` 拉起 App 包内 / `Documents/bin` 的静态 BusyBox，捕获 stdout+stderr，超时杀进程组；子进程继承当前进程沙盒状态 |
| `Sources/SandboxProbe.swift`（新增） | 用真实 I/O 探测「是否已解除沙盒」、可读/可写路径、文档符号链接；`WQSupport` 探测 `wq` 可执行文件；`SandboxBootstrap` 启动时自动创建 `root/apps/groups/sms/media` 符号链接；`AccessReport` 生成给模型看的权限自检报告 |
| `Sources/ToolCenter.swift` | 新增 `access_report` 工具；`shell` 优先走本机 BusyBox；`fs_*` 在已解除沙盒时支持绝对路径、包含隐藏文件、识别符号链接、二进制文件提示；`fs_read` 改为流式前缀读取；`fs_delete` 增加系统关键目录保护；`fs_search` 支持指定搜索起点 |
| `Sources/ChatEngine.swift` | system 提示词注入运行时权限状态（沙盒 / 终端 / WQ）；工具输出上限改为可配置 |
| `Sources/DeviceProfile.swift` | 设备档案增加「沙盒」「本机终端」两行 |
| `Sources/Models.swift` | `APISettings` 新增 `toolOutputLimit`（默认 8000，可调 2000–64000） |
| `Sources/SettingsView.swift` | 终端卡片显示 BusyBox 状态；新增工具输出上限设置 |
| `Sources/Permissions.swift` / `PluginsView.swift` / `ContentView.swift` | 能力描述、脚注、启动引导随运行时状态变化 |
| `AIChat.entitlements`（新增） | `platform-application`、`com.apple.private.security.no-sandbox`、`container-required=false`、`get-task-allow`、`AppDataContainers`、`application-groups` |
| `.github/workflows/ios.yml` | 构建前可选下载 busybox / wq；打包时先签内置二进制，再用 entitlements 签主 App |
| `Scripts/build.sh`（新增） | 本地 macOS 一键构建 + 签名脚本 |

## 二、安装前提（能力天花板取决于这一层）

1. 设备可安装 TrollStore（iOS 14–17.0 区间最稳，iOS 16.3+ 部分版本 WQ 已修复，iOS 17 部分小版本 seatbelt 有加固）。
2. 用 TrollStore 安装 `AIChat-signed.ipa`。
3. entitlements 已由 CI / `Scripts/build.sh` 通过 `codesign --entitlements` 写入；若你的安装链路会剥离 entitlements，请在安装前用 `ldid -SAIChat.entitlements Payload/AIChat.app/AIChat` 重新签一次主二进制。

安装后 App 启动即可在「能力 → 本机档案」里看到：

```
沙盒：已解除（全盘可读写）
本机终端：已内置 BusyBox
```

## 三、内置二进制放哪

| 文件 | 位置 | 作用 |
|---|---|---|
| 静态 arm64 Mach-O `busybox` | `Resources/busybox`（进 App 包根目录）或 `Documents/bin/busybox` | `shell` 工具的真实执行器 |
| `wq` / `wqcli` | `Resources/wq` 或 `Documents/bin/wq` | WQ 通道，供模型用 `shell` 直接调用 |

> 仓库里不带二进制；CI 支持两个仓库变量：`BUSYBOX_URL`、`WQ_URL`，也可以直接把文件提交到 `Resources/`。
> BusyBox 必须是 **iOS arm64 Mach-O**（不是 Linux ELF），并且要和 App 用同一种方式签名（CI 已经会对包内 `busybox`/`wq` 做 `codesign --force --sign -`）。

## 四、模型如何「完整获取」这些权限

### 1. 文件系统（全盘）

- 解除沙盒后，`fs_list / fs_read / fs_write / fs_delete / fs_search` 直接接受绝对路径：`/var/mobile/Containers/Data/Application/...`、`/var/mobile/Library/SMS/sms.db`、`/var/mobile/Containers/Shared/AppGroup/...`。
- 启动时还会在 Documents 里自动建好：`root → /`、`apps → .../Data/Application`、`groups → AppGroup 容器`、`sms → .../Library/SMS`、`media → .../Media`，模型用相对路径也能走通。
- `fs_list` 会自动显示 `[链接]` 标记；隐藏文件不再被跳过。
- 二进制文件（sqlite、plist 等）不再硬塞乱码，而是提示改用 `shell` 的 `strings / xxd / sqlite3`。

### 2. 真实 shell（fork / posix_spawn + BusyBox）

- `shell` 工具优先级：**本机 BusyBox → 远程执行器 → 沙盒模拟终端**。
- 本机模式实际执行：`posix_spawn(<bundle>/busybox, ["sh","-c",command])`，工作目录在解除沙盒后为 `/`，环境变量里 `PATH` 已包含 App 目录和 `Documents/bin`。
- 超时（默认 30s）会 `kill(-pid, SIGKILL)` 整个进程组，不会留僵尸。
- 子进程继承 App 的沙盒状态：App 是 no-sandbox，BusyBox 及其子命令同样无沙盒。

### 3. WQ（worse_query）通道

- `AIChat.entitlements` 已经带上 `com.apple.security.application-groups`（WQ 触发条件之一）。
- App 不实现漏洞本身，只提供通道：把 `wq` CLI 放进包里或 `Documents/bin`，模型通过 `shell` 调用它（例如 `wq read <目标容器路径>`），stdout 回填给模型。
- 如果把 WQ 逻辑编译成 dylib 注入主二进制（TrollStore 的 dylib 注入 / `insert_dylib`），AIChat 进程自身获得任意路径 sandbox extension 后，`fs_*` 会直接具备跨 App 读取能力——这条属于二进制注入，不改本仓库源码。

### 4. 让模型知道它有什么

`ChatEngine` 每次请求都会注入：

- `DeviceProfile.summary()`（含沙盒 / 终端状态）
- 能力清单
- 运行时说明（本机终端 / 全盘 / WQ）

另外新增 `access_report` 工具，模型可随时自查。建议在「设置 → 系统提示词」再补一段使用约定：

```
本机已通过 TrollStore + no-sandbox 解除沙盒，你拥有：
1. fs_*：全盘绝对路径读写，符号链接 root/apps/groups/sms/media 可用。
2. shell：本机真实 BusyBox，可执行任意命令、管道、重定向。
3. access_report：不确定边界时先调用它。
读大文件用 head/grep 分段；删除前确认路径不属于系统关键目录。
```

## 五、冒烟测试（装好后直接问模型）

| 测试 | 预期 |
|---|---|
| `fs_list("/var/mobile/Containers/Data/Application")` | 列出所有 App 容器 |
| `shell`：`busybox whoami; uname -a; df -h` | 真实输出，`whoami` 为 mobile |
| `shell`：`sqlite3 /var/mobile/Library/SMS/sms.db 'select count(*) from message'` | 返回短信条数（需 BusyBox 带 sqlite3 applet） |
| `shell`：`wq read <某 App 容器>/Library/Preferences/xxx.plist` | WQ 可用时返回内容 |
| `access_report` | 显示沙盒已解除、各路径可读、终端与 WQ 状态 |

## 六、边界与风险

- **能**：读/写 `/var/mobile` 下 mobile 可见目录、所有 App 容器、App Group 容器、`sms.db`、缓存、偏好；真实 fork/posix_spawn + BusyBox/curl/nc；WQ 部分版本可写。
- **不能**：内核提权、改系统分区、绕过引导链；TCC 管束的数据（照片/通讯录/定位/麦克风）仍要用户点系统弹窗。
- `get-task-allow` 与 `no-sandbox` 只适合自用；不要分发到 App Store 或第三方设备。
- WQ 是已修复/持续加固的漏洞，能否生效取决于 iOS 版本；no-sandbox 依赖 TrollStore 的签名信任链。
- 模型拿到全盘后可以读到本 App 的 API Key（Keychain / UserDefaults），这是设计代价，请自行评估。