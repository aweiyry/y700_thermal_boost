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

    private val CMD = """
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
        echo "INCUR $(cat /sys/class/power_supply/usb/current_now 2>/dev/null)"
        echo "INLIMIT $(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)"
        echo "MODVER $(grep '^version=' /data/adb/modules/y700_thermal_boost/module.prop 2>/dev/null | cut -d= -f2)"
        echo "MODRUN $(ps -A 2>/dev/null | grep -c 'y700_thermal_boost/service.sh')"
    """.trimIndent()

    fun read(): ChargeData {
        val result = runCatching { Shell.su(CMD).exec() }.getOrNull()
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
