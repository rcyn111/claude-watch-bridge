# Claude Watch Bridge

在 Apple Watch 上批准 Claude Code 的权限请求。

[English](README.md) | [中文](README.zh-CN.md)

<p align="center">
  <img src="docs/watch-mockup.png" alt="Apple Watch Claude Code 授权" width="300"/>
</p>

## 工作原理

```
Claude Code (终端) ──HTTP──> Bridge Server (Mac) ──WiFi──> iPhone App ──蓝牙──> Apple Watch
       ▲                          │          ▲
       │◄──── POST /decisions ───┘          │◄── WCSession
       └─────────────────────────────────────┘
```

当 Claude Code 需要权限执行命令、读取文件或编辑代码时，会发送 HTTP 请求到你 Mac 上的 Bridge Server。桥接服务器转发到 iPhone，iPhone 再传到 Apple Watch。你在手腕上点按**批准**或**拒绝**，决策在几秒内回传。

## 前提条件

- macOS 14+（Sonoma 或更新）
- iPhone 需 iOS 17+
- Apple Watch 需 watchOS 10+
- Mac 上安装 Node.js 18+
- 所有设备在同一 Wi-Fi 网络

## 快速开始

### 1. 安装并启动 Bridge Server

推荐使用 launchd 守护进程，开机自动启动、崩溃自动恢复：

```bash
make install        # 构建 + 安装 + 启动 launchd 守护进程
make status         # 检查运行状态
make logs           # 查看日志
```

或者在前台运行：

```bash
cd bridge
npm install
npm run build
npm start
```

没有已配对设备时，终端会显示 6 位配对码：

```
==================================================
  CLAUDE WATCH BRIDGE
==================================================
  Pairing Code: 482916
  Expires in:   120s

  Open the iOS app and enter this code to pair.
==================================================
```

### 2. 配置 Claude Code 钩子

```bash
make hooks
```

### 3. 构建并运行 iOS 应用

需要 XcodeGen：

```bash
brew install xcodegen
make ios-open
```

选择 iPhone 作为目标，构建并运行，输入配对码。

### 4. 安装 Watch 应用

在 Xcode 中选择 Watch 应用方案，安装到已配对的 Apple Watch。

### 5. 开始使用

当 Claude Code 需要权限时，手腕会震动，在手表上批准或拒绝即可。

## 运维

### 守护进程模式

`make install` 将桥接注册为 launchd 守护进程。会话持久化在 `~/.claude-watch/sessions.json`，重启桥接或电脑无需重新配对。

| 命令 | 说明 |
|------|------|
| `make install` | 构建 + 安装 + 启动守护进程 |
| `make uninstall` | 停止并移除守护进程 |
| `make restart` | 重启守护进程 |
| `make status` | 查看运行状态和连接统计 |
| `make logs` | 实时查看日志 |
| `make pair` | 生成新配对码 |
| `make hooks` | 安装 Claude Code 钩子 |
| `make hooks-remove` | 移除钩子 |

### 弹性设计

- **无设备时快速失败**：没有 iPhone/Watch 连接时，等待宽限期（默认 3 秒）后返回，不会阻塞 Claude Code。设置 `HOOK_FALLBACK_BEHAVIOR=ask` 可回退到终端提示。
- **自动重连**：iOS 应用以指数退避策略重连 SSE 流。
- **会话隔离**：`Stop` 钩子只取消该会话的待处理请求，多会话互不干扰。

## 架构

| 组件 | 技术 | 用途 |
|------|------|------|
| Bridge Server | Node.js + TypeScript + Express | 接收 Claude Code 钩子，转发到 iPhone |
| iOS 伴侣应用 | SwiftUI + WCSession | HTTP/SSE 与 Apple Watch 之间的桥梁 |
| Apple Watch 应用 | SwiftUI (watchOS) | 显示权限请求，收集用户决策 |

### API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/health` | 健康检查 |
| `POST` | `/pair` | 请求配对码 |
| `POST` | `/pair/verify` | 验证配对码，换取会话令牌 |
| `GET` | `/events` | SSE 事件流（需认证） |
| `POST` | `/hook/permission-request` | **阻塞等待** Watch 决策 |
| `POST` | `/hook/post-tool-use` | 工具使用通知 |
| `POST` | `/hook/stop` | 会话结束 |
| `POST` | `/decisions` | 提交批准/拒绝（需认证） |
| `GET` | `/pending` | 列出待处理请求（需认证） |

## 安全

- **仅本地**：默认绑定 `127.0.0.1`，不暴露到外部网络
- **配对码**：6 位随机数字，120 秒过期，仅终端显示
- **Bearer Token**：256 位随机令牌，存储在 iOS Keychain
- **无云端**：所有通信仅在你本地网络内

## 配置

通过环境变量或 `bridge/.env` 设置：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `3712` | 桥接 HTTP 端口 |
| `HOST` | `127.0.0.1` | 绑定地址 |
| `HOOK_TIMEOUT` | `300` | 等待 Watch 决策的最长秒数 |
| `HOOK_FALLBACK_BEHAVIOR` | `deny` | `deny` 拒绝 / `ask` 回退到终端 |
| `NO_CLIENT_GRACE_SECONDS` | `3` | 无设备连接时的等待宽限期 |
| `PAIRING_CODE_EXPIRY` | `120` | 配对码有效期（秒） |
| `PAIR_VERIFY_MAX_ATTEMPTS` | `5` | 每 IP 每窗口最大尝试次数 |
| `SESSION_TTL` | `604800` | 会话令牌有效期（7 天） |
| `SSE_HEARTBEAT` | `30` | SSE 心跳间隔（秒） |
| `LOG_LEVEL` | `info` | 日志级别 |
| `DATA_DIR` | `~/.claude-watch` | 数据存储目录 |
| `LOG_FILE` | `~/.claude-watch/bridge.log` | 日志文件路径 |

## 开发

```bash
make setup                # 安装依赖
cd bridge && npm run dev  # 开发模式（热重载）
make bridge-test          # 运行测试
brew install xcodegen     # iOS 开发必需
make ios-gen              # 生成 Xcode 项目
make ios-open             # 打开 Xcode
```

## 故障排查

**先检查桥接服务器：**
```bash
make status     # 运行状态和连接数
make logs       # 实时日志
```

**Watch 不显示请求：** 确保 iPhone 和 Mac 在同一 Wi-Fi，Watch 通过蓝牙连接 iPhone，WCSession 状态正常。

**Claude Code 阻塞很久后拒绝：** 没有设备连接。打开 iOS 应用或设置 `HOOK_FALLBACK_BEHAVIOR=ask`。

**配对码过期：** 运行 `make pair` 获取新码。重启桥接或电脑后无需重新配对。

**iOS 应用连不上桥接：** 必须使用 Mac 的局域网 IP（如 `192.168.1.5`），不能用 `127.0.0.1`。

## 许可证

MIT
