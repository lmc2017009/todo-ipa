# AIChat 2.3 权限与打包说明（真实边界版）

> 仅用于你自己的设备、自己的数据与研究用途。把全盘读写能力交给 LLM 意味着模型能看到你设备上的几乎所有文件，请只接入可信的模型端点（`settings.baseURL` 不要填来历不明的中转），并保持「高危工具二次确认」开启或至少清楚风险。

## 零、现实约束（务必先读，2.3 起写实）

2026-11-22 在真机（iPhone16,1 / iOS 26.4，全能签安装）实测 `access_report`：

```
uid 501；沙盒未解除；App 容器 / App Group / /var/mobile/Library / SMS / /private/var/mobile / /var/jb / /Applications 全部不可读；
仅 DCIM 可读；全盘写入不可用；内置终端未内置；WQ 未发现。
```

结论（不是 bug，是平台边界）：

1. `com.apple.private.security.no-sandbox` / `platform-application` 这类私有 entitlements **只在 TrollStore 安装或越狱环境下被 AMFI 认可**。全能签 / ESign / AltStore / Sideloadly / 自签证书在重签时会把它们全部丢弃，App 只能以普通沙盒应用运行。
2. TrollStore 只支持 **iOS 14.0–17.0**。iOS 18/26 及更新版本没有可用的 CoreTrust 类绕过，装不了。
3. `posix_spawn` 只允许执行**受信任签名**的 Mach-O。没有越狱/TrollStore 时，即使把静态 busybox 放进 App 包或 Documents，也无法 `exec`（AMFI 拒绝）。
4. 所以「全盘 + 真终端」在这类设备上**不可能**通过改代码获得；任何声称能做到的 App 都在用别的漏洞或需要越狱。

2.3 的做法是：**把不可能的部分讲清楚，把可能的部分做实**。

## 一、2.3 改了什么（相对 2.2）

| 文件 | 改动 |
|---|---|
| `Sources/DirectoryGrant.swift`（新增） | 目录授权：`UIDocumentPickerViewController` 让用户选一个目录 → 存成 security-scoped bookmark → 用 `grant:标签/子路径` 读写。**普通签名即可生效**，是 iOS 上免越狱唯一的跨沙盒文件通道（可以选「我的 iPhone」里其他 App 的文件夹） |
| `Sources/ToolCenter.swift` | 新增 `dir_grant` / `dir_list` / `dir_revoke`；`resolve()` 支持 `grant:` 前缀（越界校验仍保留）；`fs_list` 在根目录列出已授权目录；`fs_*` 的报错改为可执行的下一步建议；`shell` 在没有真实终端时明确说明「没有 POSIX 执行能力」，不再给出误导性的「沙盒内不支持 busybox」 |
| `Sources/SandboxProbe.swift` | `AccessReport` 增加 TCC 授权状态（相册 / 通讯录 / 日历 / 提醒 / 相机 / 麦克风）、未解除沙盒的原因结论、已授权目录列表；`osVersion` 改用 `ProcessInfo`（可在后台线程安全调用） |
| `Sources/ChatEngine.swift` | system 提示词新增「沙盒受限模式」段落：禁止模型反复尝试 `/var/mobile`、`/var/containers`、`sms.db`，引导走 `dir_grant` + `grant:` 路径；已授权目录直接列进提示词 |
| `Sources/SettingsView.swift` | 新增「已授权目录」卡片：列表、删除、`添加目录…`（弹系统选择器） |
| `project.yml` | 版本 2.3 (4)；新增 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`（App 的 Documents 会出现在「文件」App 里，方便拖放日志/文件） |

2.2 留下的能力（`LocalShell` / `SandboxBootstrap` / `WQSupport` / entitlements / CI 签名链）**全部保留**：在 iOS ≤17 的 TrollStore 设备上依旧按原设计工作，不降级。

## 二、能力天花板对照（按安装方式）

| 安装方式 | 沙盒 | 真终端 | 跨 App 文件 | 备注 |
|---|---|---|---|---|
| TrollStore（iOS 14–17.0） | 可解除 | 可（内置 busybox） | 可（全盘） | 本仓库的完整形态 |
| 越狱 | 可解除 | 可 | 可 | 同上，还能装 `wq` |
| 全能签 / ESign / AltStore / 自签 | **不可** | 不可 | 仅授权目录 + 相册 | 2.3 的 `dir_grant` 路线 |
| 远程执行器 | 不涉及 | 可（在电脑上） | 可（电脑上） | 设置里填 `terminalHost`，App 只做转发 |

## 三、免越狱怎么用（2.3 主推）

1. 装好后进「设置 → 已授权目录 → 添加目录…」，选一个目录（例如「我的 iPhone → 某个 App」，或 iCloud Drive 里的文件夹）。
2. 对模型说：`读取 grant:<标签> 里的文件列表`。模型会调用 `fs_list("grant:<标签>")`。
3. 想给更多目录，就多授权几个；不想要了就点垃圾桶撤销。
4. 相册/通讯录/日历/提醒依旧走专用工具（首次会弹 TCC 授权）。

> 说明：`dir_grant` 弹的是系统选择器，只有用户点选才会授权，模型无法自己扩权；bookmark 存在 `UserDefaults`，App 重启后仍有效。

## 四、TrollStore 路线（iOS ≤17，保持原样）

1. 设备可安装 TrollStore（iOS 14–17.0 区间最稳）。
2. 用 TrollStore 安装 `AIChat.ipa`。
3. entitlements 已由 CI 通过 `codesign --entitlements` 写入；若安装链路会剥离 entitlements，用 `ldid -SAIChat.entitlements Payload/AIChat.app/AIChat` 重签主二进制。

安装后「能力 → 本机档案」应显示：

```
沙盒：已解除（全盘可读写）
本机终端：已内置 BusyBox
```

## 五、内置二进制放哪（仅 TrollStore / 越狱有意义）

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