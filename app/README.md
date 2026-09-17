# Y700 充电监控 App

配合 [Y700 温控模块](../README.md) 使用的实时充电监控 App（libsu 直读 `/sys` 节点）。

## 功能

**实时界面**（每秒刷新，每 2 秒落点）：

- 环形电量仪表 + 充电状态
- **三张实时曲线**：功率 / 电量 / 温度
- 充电协议（PD/PPS/DCP/SDP…）、充电阶段
- 电池：电流、电压、功率、**真实温度**、充电电流上限（CCL）
- 输入（充电器）：输入电压、电流、功率、输入电流上限
- 模块版本 / 运行状态

**充电存档**：

- 自动识别充电开始/结束，全程记录采样点（功率/输入功率/电量/温度/电流/电压）
- **历史记录**：列表（充入电量 / 时长 / 峰值功率 / 协议 / 能量）+ 详情页（完整统计 + 该次曲线）
- 支持单条删除 / 清空

## 数据说明

- App 数据保存在 **App 私有目录**（`/data/data/com.y700.charge/files/`），
  **不读取也不写入模块的 `/sdcard/充电日志/`**，两者完全独立
- **温度显示的是真实电池温度**（`power_supply/battery/temp`）——模块伪装的是 thermal 温区，
  这个只读节点伪装不了；监控真实温度才是正确的
- **PPS 快充下输入电流不可读**：平台不向用户空间暴露（实测确认），此时显示「不可读」而非 0；
  快充请以**电池功率**为准

## 技术栈

- Kotlin + Jetpack Compose (Material3)
- [libsu](https://github.com/topjohnwu/libsu) 读取 `/sys/class/power_supply/*` 与 PMIC IIO ADC 节点
  （需 root / KernelSU / Magisk）

## 构建

```bash
# 需要 JDK 17+ 与 Android SDK (compileSdk 34)
./gradlew assembleDebug
# 产物: app/build/outputs/apk/debug/app-debug.apk
```

## 使用

1. 从 [Releases](https://github.com/aweiyry/y700_thermal_boost/releases) 下载 `y700_charge_monitor_vX.X.apk` 安装
2. 打开 App，首次会弹 KernelSU/Magisk root 授权，点「允许」
3. 即可看到实时充电信息，右上角「历史记录」查看每次充电存档
