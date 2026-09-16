# Y700 充电监控 App

配合 [Y700 温控模块](../README.md) 使用的实时充电监控 App（方案A：libsu 直读 `/sys` 节点）。

## 功能

实时显示（每 1 秒刷新）：

- 充电状态 / 充电协议（PD/PPS/DCP/SDP…）/ 充电类型
- 电池：电流、电压、功率、真实温度、充电电流上限（CCL）
- 输入（充电器）：输入电压、电流、功率、输入电流上限
- 模块版本 / 运行状态

## 技术栈

- Kotlin + Jetpack Compose (Material3)
- [libsu](https://github.com/topjohnwu/libsu) 读取 `/sys/class/power_supply/*`（需 root / KernelSU / Magisk）

## 构建

```bash
# 需要 JDK 17+ 与 Android SDK (compileSdk 34)
./gradlew assembleDebug
# 产物: app/build/outputs/apk/debug/app-debug.apk
```

## 使用

1. 安装 APK
2. 打开 App，首次会弹 KernelSU/Magisk root 授权，点「允许」
3. 即可看到实时充电信息
