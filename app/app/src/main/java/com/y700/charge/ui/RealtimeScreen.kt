package com.y700.charge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.y700.charge.data.ChargeData
import com.y700.charge.data.ChargeSample
import com.y700.charge.data.ChargeSession

@Composable
fun RealtimeScreen(
    data: ChargeData,
    rootState: String,
    samples: List<ChargeSample>,
    session: ChargeSession?,
    sessionCount: Int,
    onOpenHistory: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(14.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Y700 充电监控", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            TextButton(onClick = onOpenHistory) { Text("历史记录 ($sessionCount)") }
        }
        Text(
            "模块 ${data.moduleVersion.ifBlank { "—" }} · ${if (data.moduleRunning) "运行中" else "未运行"} · $rootState",
            fontSize = 11.sp, color = Color.Gray
        )
        Spacer(Modifier.height(12.dp))

        Card(Modifier.fillMaxWidth()) {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                BatteryGauge(data.capacity, data.isCharging, Modifier.size(110.dp))
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    InfoRow("充电协议", data.protocolLabel)
                    InfoRow("电池功率", fmtW(data.batteryPowerW))
                    InfoRow("输入功率", fmtW(data.inputPowerW))
                    InfoRow("电池温度", fmtC(data.batteryTempC))
                }
            }
        }

        Card(Modifier.fillMaxWidth().padding(top = 10.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text("电池", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(6.dp))
                InfoRow("电流", fmtA(data.batteryCurrentUa))
                InfoRow("电压", fmtV(data.batteryVoltageUv))
                if (data.cclMax > 0) InfoRow("充电电流上限", fmtA(data.ccl) + " / " + fmtA(data.cclMax))
            }
        }

        Card(Modifier.fillMaxWidth().padding(top = 10.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text("输入 (充电器)", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(6.dp))
                InfoRow("输入电压", fmtV(data.inputVoltageUv))
                // 充电中但输入电流为 0 = 节点不可读(PPS 下旧节点恒为 0), 明确提示而非显示骗人的 0
                val unavailable = data.isCharging && !data.inputReadable
                InfoRow("输入电流", if (unavailable) "不可读" else fmtA(data.inputCurrentUa))
                InfoRow("输入功率", if (unavailable) "不可读" else fmtW(data.inputPowerW))
                if (data.inputLimitUa > 0) InfoRow("输入电流上限", fmtA(data.inputLimitUa))
                InfoRow("充电阶段", data.chargeType.ifBlank { "—" })
            }
        }

        session?.let { s ->
            Card(Modifier.fillMaxWidth().padding(top = 10.dp)) {
                Column(Modifier.padding(14.dp)) {
                    Text("本次充电", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(6.dp))
                    InfoRow("开始", fmtFull(s.startTime))
                    InfoRow("已充入", "${s.chargedPercent}%  (${s.startCap}% → ${s.endCap}%)")
                    InfoRow("时长", fmtDuration(s.endTime - s.startTime))
                    InfoRow("峰值 / 平均功率", "${fmtW(s.peakPowerW)} / ${fmtW(s.avgPowerW)}")
                    InfoRow("峰值 / 平均温度", "${fmtC(s.peakTempC)} / ${fmtC(s.avgTempC)}")
                    InfoRow("充入能量", fmtWh(s.energyWh))
                }
            }
        }

        Spacer(Modifier.height(14.dp))
        ChartCard(
            title = "功率 / 时间",
            points = samples.toPoints { it.powerW.toFloat() },
            lineColor = Color(0xFF4CAF50),
            unit = "W",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        ChartCard(
            title = "电量 / 时间",
            points = samples.toPoints { it.capacity.toFloat() },
            lineColor = Color(0xFF2196F3),
            unit = "%",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        ChartCard(
            title = "温度 / 时间",
            points = samples.toPoints { it.tempC.toFloat() },
            lineColor = Color(0xFFFF9800),
            unit = "°",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        Spacer(Modifier.height(20.dp))
    }
}
