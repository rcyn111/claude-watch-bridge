# Claude Watch Bridge

在 Apple Watch 上批准 Claude Code 的权限请求。

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

推荐使用 launchd 守护进程，**开机自动启动、崩溃自动恢复**：

```bash
make install        # 构建 + 安装 + 启动 launchd 守护进程
make status         # 检查运行状态
make logs           # 查看日志
```

如果想在前台运行：

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

这会将 Watch 授权钩子写入 `~/.claude/settings.json`。

### 3. 构建并运行 iOS 应用

打开 Xcode 项目（需要 XcodeGen）：

```bash
brew install xcodegen
make ios-open
```

选择你的 iPhone 作为目标，构建并运行。输入终端显示的 6 位配对码。

### 4. 安装 Watch 应用

在 Xcode 中选择 Watch 应用方案，安装到你已配对的 Apple Watch 上。或在 iPhone 的 Watch 应用中启用"在 Apple Watch 上显示应用"。

### 5. 开始使用

搞定。当 Claude Code 需要权限时，你会感到手腕震动，在手表上批准或拒绝即可。

## 运维

### 守护进程模式

`make install` 将桥接注册为 launchd 守护进程，开机启动、崩溃重启。配对会话持久化在 `~/.claude-watch/sessions.json`，**重启桥接或重启电脑无需重新配对**——iOS 应用会自动重连。

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

- **无设备时快速失败**：没有 iPhone/Watch 连接时，权限请求在短暂等待（默认 3 秒）后返回，不会让 Claude Code 一直阻塞。设置 `HOOK_FALLBACK_BEHAVIOR=ask` 可回退到终端提示。
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

在环境变量或 `bridge/.env` 中设置：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `3712` | 桥接 HTTP 端口 |
| `HOST` | `127.0.0.1` | 绑定地址 |
| `HOOK_TIMEOUT` | `300` | 等待 Watch 决策的最长秒数 |
| `HOOK_FALLBACK_BEHAVIOR` | `deny` | 超时/无设备时的行为：`deny` 拒绝，`ask` 回退到终端 |
| `NO_CLIENT_GRACE_SECONDS` | `3` | 无设备连接时的等待宽限期 |
| `PAIRING_CODE_EXPIRY` | `120` | 配对码有效期（秒） |
| `PAIR_VERIFY_MAX_ATTEMPTS` | `5` | 每 IP 每窗口最大尝试次数 |
| `SESSION_TTL` | `604800` | 会话令牌有效期（秒，7 天） |
| `SSE_HEARTBEAT` | `30` | SSE 心跳间隔（秒） |
| `LOG_LEVEL` | `info` | 日志级别 |
| `DATA_DIR` | `~/.claude-watch` | 数据存储目录 |
| `LOG_FILE` | `~/.claude-watch/bridge.log` | 日志文件路径 |

## 开发

```bash
# 安装依赖
make setup

# 开发模式启动（热重载）
cd bridge && npm run dev

# 运行测试
make bridge-test

# 生成 Xcode 项目（需要 XcodeGen）
brew install xcodegen
make ios-gen

# 打开 Xcode
make ios-open
```

## 故障排查

**先检查桥接服务器：**
```bash
make status     # 运行状态和连接数
make logs       # 实时日志
```

**Watch 不显示请求：**
- 确保 iPhone 和 Mac 在同一 Wi-Fi
- 检查 Apple Watch 是否通过蓝牙连接 iPhone
- 在 iOS 应用 Dashboard 中查看 WCSession 状态
- 检查桥接日志中的 SSE 连接状态（`make logs`）

**Claude Code 阻塞很久后拒绝：**
- 没有设备连接。打开 iOS 应用让它自动重连，或设置 `HOOK_FALLBACK_BEHAVIOR=ask` 回退到终端提示。

**配对码过期：**
- 运行 `make pair` 获取新码。重启桥接或电脑后无需重新配对——会话已持久化，iOS 应用会自动重连。

**iOS 应用连不上桥接：**
- 手机必须使用你 **Mac 的局域网 IP**（如 `192.168.1.5`），不能用 `127.0.0.1`（那指向手机自己）。填过的地址会自动保存。

**iPhone 上显示"不可达"：**
- 打开 iPhone 的 Watch 应用
- 确保安装了 Claude Watch 应用
- 初次配对时保持 iPhone 应用在前台

## 许可证

MIT
