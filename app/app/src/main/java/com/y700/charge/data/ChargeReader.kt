package com.y700.charge.data

import com.topjohnwu.superuser.Shell

data class ChargeData(
    val batteryCurrentUa: Long = 0,
    val batteryVoltageUv: Long = 0,
    val batteryTempDeciC: Int = 0,
    val capacity: Int = 0,
    val status: String = "",
    val chargeType: String = "",
    val ccl: Long = 0,
    val cclMax: Long = 0,
    val protocol: String = "",
    val inputVoltageUv: Long = 0,
    val inputCurrentUa: Long = 0,
    val inputLimitUa: Long = 0,
    val moduleVersion: String = "",
    val moduleRunning: Boolean = false,
    val readOk: Boolean = false,
) {
    val batteryPowerW: Double get() = (batteryVoltageUv * kotlin.math.abs(batteryCurrentUa)) / 1e12
    val inputPowerW: Double get() = (inputVoltageUv * kotlin.math.abs(inputCurrentUa)) / 1e12
    val batteryTempC: Double get() = batteryTempDeciC / 10.0
    val isCharging: Boolean get() = status.equals("Charging", ignoreCase = true)
    val protocolLabel: String get() = mapProtocol(protocol)

    /**
     * 输入电流/功率是否可信。
     * PD/PPS 下部分平台会返回极小的垃圾值(如 0.01A / 0.1W), 用能量守恒剔除:
     * 充电时输入功率必然 >= 电池功率, 否则该读数无效。
     * 仅对 PD/PPS 生效 —— SDP/DCP 下节点可靠, 不做校验以免电池读数尖峰误判。
     */
    val inputReadable: Boolean
        get() {
            if (inputCurrentUa <= 0) return false
            val p = protocol.uppercase()
            val isPdPps = p.contains("PPS") || p.startsWith("PD")
            if (isPdPps && batteryPowerW > 1.0 && inputPowerW < batteryPowerW * 0.5) return false
            return true
        }
}

fun mapProtocol(raw: String): String = when (raw.uppercase()) {
    "PD_PPS" -> "PD/PPS"
    "PD_DRP", "PD" -> "PD"
    "DCP" -> "DCP"
    "CDP" -> "CDP"
    "SDP" -> "SDP"
    "SCP" -> "SCP"
    "VOOC", "SUPERVOOC" -> "VOOC"
    "", "UNKNOWN" -> "未识别"
    else -> raw
}

object ChargeReader {

    private const val USB_CURRENT = "/sys/class/power_supply/usb/current_now"

    /** PMIC IIO ADC 输入电流节点; null = 尚未解析 */
    @Volatile
    private var iinNode: String? = null

    private fun resolveIinNode(): String {
        val out = runCatching {
            Shell.su(
                "find /sys/devices/platform/soc -maxdepth 8 -name 'in_current_*_iin_input' 2>/dev/null" +
                    " | grep pmih010x_iin | head -1"
            ).exec().out
        }.getOrNull() ?: return ""
        return out.firstOrNull()?.trim().orEmpty()
    }

    /** 输入电流来源: 优先 IIO ADC(PPS 下唯一可用), 回退 usb/current_now */
    private fun inputCurrentPath(): String {
        if (iinNode == null) iinNode = resolveIinNode()
        val n = iinNode
        return if (!n.isNullOrEmpty()) n else USB_CURRENT
    }

    private fun buildCmd(): String {
        val iin = inputCurrentPath()
        return """
        echo "BATCUR $(cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
        echo "BATVOL $(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)"
        echo "BATTEMP $(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
        echo "CAP $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
        echo "STATUS $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
        echo "CTYPE $(cat /sys/class/power_supply/battery/charge_type 2>/dev/null)"
        echo "CCL $(cat /sys/class/power_supply/battery/charge_control_limit 2>/dev/null)"
        echo "CCLMAX $(cat /sys/class/power_supply/battery/charge_control_limit_max 2>/dev/null)"
        echo "PROTO $(cat /sys/class/power_supply/usb/real_type 2>/dev/null)"
        echo "INVOL $(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null)"
        echo "INCUR $(cat "$iin" 2>/dev/null)"
        echo "INLIMIT $(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)"
        echo "MODVER $(grep '^version=' /data/adb/modules/y700_thermal_boost/module.prop 2>/dev/null | cut -d= -f2)"
        echo "MODRUN $(if grep -qa 'y700_thermal_boost/service.sh' /proc/$(cat /data/local/tmp/y700_thermal_boost.pid 2>/dev/null)/cmdline 2>/dev/null; then echo 1; else grep -la 'y700_thermal_boost/service.sh' /proc/[0-9]*/cmdline 2>/dev/null | head -1 | wc -l; fi)"
        """.trimIndent()
    }

    fun read(): ChargeData {
        val result = runCatching { Shell.su(buildCmd()).exec() }.getOrNull()
        if (result == null || !result.isSuccess) return ChargeData()
        val map = mutableMapOf<String, String>()
        for (line in result.out) {
            val i = line.indexOf(' ')
            if (i > 0) map[line.substring(0, i)] = line.substring(i + 1).trim()
        }
        fun s(key: String) = map[key] ?: ""
        fun l(key: String) = s(key).toLongOrNull() ?: 0L
        fun i(key: String) = s(key).toIntOrNull() ?: 0
        val modRun = s("MODRUN").toIntOrNull() ?: 0
        return ChargeData(
            batteryCurrentUa = l("BATCUR"),
            batteryVoltageUv = l("BATVOL"),
            batteryTempDeciC = i("BATTEMP"),
            capacity = i("CAP"),
            status = s("STATUS"),
            chargeType = s("CTYPE"),
            ccl = l("CCL"),
            cclMax = l("CCLMAX"),
            protocol = s("PROTO"),
            inputVoltageUv = l("INVOL"),
            inputCurrentUa = l("INCUR"),
            inputLimitUa = l("INLIMIT"),
            moduleVersion = s("MODVER"),
            moduleRunning = modRun > 0,
            readOk = true,
        )
    }
}
