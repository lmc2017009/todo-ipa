# AI 对话（AIChat）2.1

纯 SwiftUI 的 iOS AI 客户端：自己填 API 端点和密钥，模型能力取决于你接入的服务；同时把 iPhone 能授权的设备能力全部开放给模型调用。

## 一、功能

| 模块 | 内容 |
|---|---|
| 聊天 | 多会话列表、流式输出、Markdown、代码块、消息复制、停止生成 |
| 输入 | 相册图片（自动压缩成 base64）、文本文件导入、多图（最多 4 张） |
| 推理 | 深度思考档位（关/低/中/高），按服务商映射参数，服务端不支持时自动降级重试 |
| 联网 | DuckDuckGo → Bing 兜底，检索结果附来源列表并注入上下文 |
| 模型 | `GET /models` 拉取列表、过滤非对话模型、支持手填模型名、连接测试显示耗时 |
| 能力 | 13 项设备能力，逐项授权、状态显示、一键授权、总开关 |
| 工具 | OpenAI `tools` 协议，最多 5 轮工具循环，工具结果回填模型 |
| 安全 | 高危工具二次确认（写入 / 删除 / 终端 / 建提醒），可关 |
| UI | iOS 26 Liquid Glass（`glassEffect`），低版本自动退化毛玻璃；全部 SF Symbols，无 emoji |

## 二、13 项能力

| 能力 | 是否需要系统弹窗 | 说明 |
|---|---|---|
| 设备档案 | 否 | 机型、芯片标识、系统、屏幕、电量、内存、存储、网络 IP、低电量、语言时区、时间 |
| 文件读写 | 否 | App 文档目录内的列目录 / 读 / 写 / 删 / 按名字和内容搜索 |
| 剪贴板 | 否 | 读 / 写文本 |
| 运动传感器 | 否 | 加速度计（陀螺仪视硬件） |
| 相册 | 是 | 把最近照片复制到沙盒 `photos/`，返回路径 |
| 相机 | 是 | 授权相机 |
| 麦克风 | 是 | 授权麦克风 |
| 定位 | 是 | 当前经纬度与精度 |
| 通讯录 | 是 | 按姓名搜索，返回前 10 条与号码 |
| 日历 | 是 | 查询未来 N 天日程 |
| 提醒事项 | 是 | 创建提醒（可带时间） |
| 通知 | 是 | 定时本地通知 |
| 终端 | 否（App 内开关） | 沙盒模拟终端；填了远程地址则转发真 shell |

## 三、工具列表

`device_info`、`fs_list`、`fs_read`、`fs_write`、`fs_delete`、`fs_search`、`shell`、`clipboard`、`motion`、`location`、`contacts_search`、`calendar_events`、`reminder_create`、`notify`、`photos_recent`

工具会按「能力中心」的授权状态动态增减，未授权的能力不会暴露给模型。

## 四、接一个真终端（可选）

未越狱设备没有系统 shell。要让模型跑真实命令，在自己电脑上起一个 HTTP 执行器，手机和电脑同一局域网：

```python
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, subprocess

TOKEN = ""  # 填了就要求 X-Token 一致

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        if TOKEN and self.headers.get("X-Token") != TOKEN:
            self.send_response(401); self.end_headers(); return
        n = int(self.headers.get("Content-Length", 0))
        cmd = json.loads(self.rfile.read(n) or b"{}").get("cmd", "")
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        body = (p.stdout + p.stderr).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("0.0.0.0", 8765), H).serve_forever()
```

运行 `python3 runner.py`，在 App 设置 → 终端里填 `http://电脑IP:8765`，令牌与脚本里的 `TOKEN` 一致。

> 注意：这个执行器等于把电脑的 shell 暴露给能访问该端口的人。务必只在内网使用，并设置 TOKEN。

## 五、边界（必须知道）

- **无越狱没有 root**：不能改系统目录、不能读其他 App 的沙盒、不能拿短信/通话记录。
- **系统权限只能靠用户点弹窗**：App 无法静默授权，被拒绝后要手动去系统设置打开。
- **沙盒文件 ≠ 全盘**：只能读写本 App 的 Documents，其他位置需要通过系统文件选择器导入。
- **联网检索靠网页解析**：第三方页面结构变化时可能失败，失败会退回模型自身知识。
- **工具能力取决于模型**：只有支持 OpenAI function calling 的模型才能真正调用；不支持时会自动退回纯聊天。

## 六、构建

- XcodeGen 工程即代码，`project.yml` 里含全部 Info.plist 权限说明。
- GitHub Actions 强选 Xcode 26，`CODE_SIGNING_ALLOWED=NO` 构建，ad-hoc `codesign --sign -`，打包成未签名 IPA。
- 仓库：`lmc2017009/todo-ipa`（仓库名沿用历史）；产物：`AIChat-unsigned.ipa`。
- 版本：2.2 (3)，Bundle ID `com.operit.aichat`，最低 iOS 16.0，仅 iPhone。

## 七、2.2 权限增强（TrollStore / no-sandbox / 本机 BusyBox / WQ）

2.2 在原有 13 项能力之上，把「模型能拿到的权限」做成可落地的三层：

1. **本机真实终端**：`shell` 工具用 `posix_spawn` 拉起包内静态 BusyBox（`Resources/busybox` 或 `Documents/bin/busybox`），子进程继承 no-sandbox，真 fork、真进程。
2. **全盘文件**：解除沙盒后 `fs_*` 直接支持绝对路径，并自动准备 `root/apps/groups/sms/media` 符号链接；新增 `access_report` 工具让模型自查权限边界。
3. **WQ 通道**：`AIChat.entitlements` 带 `application-groups`，配合包内/文档内的 `wq` CLI，模型可用 `shell` 调用；也可用 dylib 注入让进程自持 sandbox extension。

签名与安装步骤、冒烟测试、边界说明见 [`PERMISSIONS.md`](PERMISSIONS.md)。
CI（`.github/workflows/ios.yml`）与本地脚本（`Scripts/build.sh`）会自动对内置二进制与主 App 签名，并注入 entitlements。