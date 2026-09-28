# Bobobei BLE App

一个不依赖 Cove、MCP 客户端或特定服务器的 **啵啵贝（广播名 SOSEXY）原生
App 蓝牙接入参考实现**。

仓库提供：

- 可复用的 Swift Package（iOS 15+）
- SOSEXY GATT UUID 与 12 字节控制帧
- 串行 write-with-response
- 每 400 ms 单包保活
- 写入超时、掉线重连与 GATT 重新发现
- SwiftUI 最小接入示例
- Android 移植要点

它不提供云服务器、AI、MCP 或现成产品 UI。你可以把 BLE 层接进自己的 App，
再选择本地按钮、WebSocket、SSE、HTTPS 或其他经过鉴权的高层控制来源。

## 结论：原生 App 可以，iPhone PWA 不行

“有 App 就可以”准确地说是：**自建原生 App 集成这套 BLE 代码就可以**。
一个没有实现 BLE 中央设备逻辑的普通 App 不会自动获得控制能力。

- iOS：使用 CoreBluetooth，并加入蓝牙用途说明；需要后台接收 BLE 事件时声明
  `bluetooth-central`。
- Android：使用系统 BLE API，并处理对应权限与前台服务策略。
- iPhone PWA / Safari：WebKit 目前未实现 Web Bluetooth；而且网页后台生命周期
  也不适合持续保活和可靠自动重连。因此本仓库选择原生 App。

官方资料：

- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple: Core Bluetooth background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [WebKit: Web Bluetooth is not implemented](https://webkit.org/tracking-prevention/)

## 快速接入 iOS App

### 1. 添加 Package

在 Xcode 中把本仓库作为 Swift Package dependency，或直接复制
`Sources/BobobeiBLE` 到项目。

### 2. 配置权限

把 [`Examples/iOS/Info.plist.snippet.xml`](Examples/iOS/Info.plist.snippet.xml)
里的键合并到 App 的 `Info.plist`。

### 3. 用户主动扫描并选择设备

```swift
@StateObject private var toy = BobobeiCentral()

Button("扫描") { toy.scan() }

ForEach(toy.devices) { device in
    Button(device.name) { toy.connect(device.id) }
}
```

不要在 App 启动时偷偷扫描或自动选择未知设备。

### 4. 发控制指令

```swift
try await toy.setLevels(.init(
    motion: 35,
    vibration: 20,
    rotation: 0
))

try await toy.stop()
```

完整 UI 见 [`BobobeiDemoView.swift`](Examples/iOS/BobobeiDemoView.swift)。

## 为什么这个版本更稳

1. 三个控制帧严格串行发送，每包等待 GATT 回执。
2. 保活每 400 ms 只重复一个当前状态包，不是每次连发三包。
3. 5 秒没有写入回执就触发重连，重连后重新发现特征。
4. 控制调用会等待连接恢复，不把“已排队”冒充“已经执行”。

协议细节见 [`docs/PROTOCOL.md`](docs/PROTOCOL.md)。

## 安全与边界

- 强度统一限制为 0–100。
- 保留醒目的 Stop 与 Disconnect。
- 远程控制必须有用户明确授权、鉴权和可撤销会话。
- 不要把控制接口裸露到公网，也不要接受任意 GATT 字节。
- BLE 断开时无法保证补发“停止”包；硬件本身仍应有物理关机方式。
- 连接成功只说明协议写入成功，不代表任何主观体验或身体状态。

## 已验证范围

协议帧与 Swift 状态机基于一台广播名以 `SOSEXY` 开头的啵啵贝设备验证。
不同批次固件可能不同；请先用 nRF Connect 等工具确认 UUID。

## 致谢

- [51enuxu/sosexy-ble-control](https://github.com/51enuxu/sosexy-ble-control)：早期 SOSEXY 协议逆向工作
- [tutu-kitty/Toy-Relay-AI-mcp-SOSEXY](https://github.com/tutu-kitty/Toy-Relay-AI-mcp-SOSEXY)：公开协议文档与浏览器中继实现

## License

MIT
