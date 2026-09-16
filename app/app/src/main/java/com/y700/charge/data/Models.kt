package com.y700.charge.data

import org.json.JSONArray
import org.json.JSONObject

/** 一次采样点 (用于绘图与统计) */
data class ChargeSample(
    val t: Long,            // 采样时间 (epoch ms)
    val powerW: Double,     // 电池功率 W
    val inputW: Double,     // 输入功率 W
    val capacity: Int,      // 电量 %
    val tempC: Double,      // 电池温度 °C
    val currentA: Double,   // 电池电流 A (充电为正)
    val voltageV: Double,   // 电池电压 V
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("t", t)
        put("p", powerW)
        put("ip", inputW)
        put("c", capacity)
        put("tc", tempC)
        put("i", currentA)
        put("v", voltageV)
    }

    companion object {
        fun fromJson(o: JSONObject) = ChargeSample(
            t = o.optLong("t"),
            powerW = o.optDouble("p"),
            inputW = o.optDouble("ip"),
            capacity = o.optInt("c"),
            tempC = o.optDouble("tc"),
            currentA = o.optDouble("i"),
            voltageV = o.optDouble("v"),
        )
    }
}

/** 一次完整充电会话 */
data class ChargeSession(
    val startTime: Long,
    val endTime: Long,
    val startCap: Int,
    val endCap: Int,
    val protocol: String,
    val samples: List<ChargeSample> = emptyList(),
    val complete: Boolean = false,
) {
    val durationMs: Long get() = (endTime - startTime).coerceAtLeast(0)
    val chargedPercent: Int get() = endCap - startCap

    val peakPowerW: Double get() = samples.maxOfOrNull { it.powerW } ?: 0.0
    val avgPowerW: Double get() = samples.takeIf { it.isNotEmpty() }?.let { s -> s.sumOf { it.powerW } / s.size } ?: 0.0
    val peakInputW: Double get() = samples.maxOfOrNull { it.inputW } ?: 0.0
    val avgInputW: Double get() = samples.takeIf { it.isNotEmpty() }?.let { s -> s.sumOf { it.inputW } / s.size } ?: 0.0
    val peakTempC: Double get() = samples.maxOfOrNull { it.tempC } ?: 0.0
    val avgTempC: Double get() = samples.takeIf { it.isNotEmpty() }?.let { s -> s.sumOf { it.tempC } / s.size } ?: 0.0
    val peakCurrentA: Double get() = samples.maxOfOrNull { it.currentA } ?: 0.0

    /** 电池充入能量 Wh (对功率按时间积分) */
    val energyWh: Double get() = integrate { it.powerW }

    /** 充电器输入能量 Wh */
    val inputEnergyWh: Double get() = integrate { it.inputW }

    private fun integrate(sel: (ChargeSample) -> Double): Double {
        if (samples.size < 2) return 0.0
        var e = 0.0
        for (i in 1 until samples.size) {
            val dtH = (samples[i].t - samples[i - 1].t) / 3_600_000.0
            if (dtH <= 0) continue
            e += (sel(samples[i - 1]) + sel(samples[i])) / 2.0 * dtH
        }
        return e
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("startTime", startTime)
        put("endTime", endTime)
        put("startCap", startCap)
        put("endCap", endCap)
        put("protocol", protocol)
        put("complete", complete)
        put("samples", JSONArray().apply { samples.forEach { put(it.toJson()) } })
    }

    companion object {
        fun fromJson(o: JSONObject): ChargeSession {
            val arr = o.optJSONArray("samples") ?: JSONArray()
            val list = ArrayList<ChargeSample>(arr.length())
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { list.add(ChargeSample.fromJson(it)) }
            }
            return ChargeSession(
                startTime = o.optLong("startTime"),
                endTime = o.optLong("endTime"),
                startCap = o.optInt("startCap"),
                endCap = o.optInt("endCap"),
                protocol = o.optString("protocol"),
                samples = list,
                complete = o.optBoolean("complete"),
            )
        }
    }
}
