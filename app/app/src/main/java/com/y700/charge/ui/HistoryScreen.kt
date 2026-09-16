package com.y700.charge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.y700.charge.data.ChargeSession

@Composable
fun HistoryScreen(
    sessions: List<ChargeSession>,
    onBack: () -> Unit,
    onOpen: (ChargeSession) -> Unit,
    onDelete: (Long) -> Unit,
    onClearAll: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onBack) { Text("← 返回") }
                Text("历史记录", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            if (sessions.isNotEmpty()) {
                TextButton(onClick = onClearAll) { Text("清空", color = Color(0xFFE57373)) }
            }
        }

        if (sessions.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("暂无充电记录", color = Color.Gray)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(horizontal = 14.dp)) {
                items(sessions, key = { it.startTime }) { s ->
                    SessionRow(s, onClick = { onOpen(s) }, onDelete = { onDelete(s.startTime) })
                }
                item { Spacer(Modifier.height(20.dp)) }
            }
        }
    }
}

@Composable
private fun SessionRow(s: ChargeSession, onClick: () -> Unit, onDelete: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
        Row(
            Modifier.padding(start = 14.dp, top = 12.dp, bottom = 12.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(fmtDate(s.startTime), fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    if (!s.complete) {
                        Spacer(Modifier.padding(horizontal = 4.dp))
                        Text("进行中", fontSize = 11.sp, color = Color(0xFF4CAF50))
                    }
                }
                Spacer(Modifier.height(3.dp))
                Text(
                    "+${s.chargedPercent}%  ·  ${fmtDuration(s.durationMs)}  ·  峰值 ${fmtW(s.peakPowerW)}",
                    fontSize = 12.sp, color = Color.Gray
                )
                Text(
                    "${s.protocol}  ·  ${fmtWh(s.energyWh)}  ·  ${s.samples.size} 采样",
                    fontSize = 11.sp, color = Color(0xFF888888)
                )
            }
            TextButton(onClick = onClick) { Text("详情") }
            TextButton(onClick = onDelete) { Text("删除", color = Color(0xFFE57373)) }
        }
    }
}

@Composable
fun SessionDetailScreen(session: ChargeSession, onBack: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("← 返回") }
            Text("充电详情", fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp)) {
                Text("基本信息", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(6.dp))
                InfoRow("开始时间", fmtFull(session.startTime))
                InfoRow("结束时间", if (session.complete) fmtFull(session.endTime) else "进行中")
                InfoRow("时长", fmtDuration(session.durationMs))
                InfoRow("充电协议", session.protocol)
                InfoRow("电量变化", "${session.startCap}% → ${session.endCap}%  (+${session.chargedPercent}%)")
                InfoRow("充入能量", fmtWh(session.energyWh))
            }
        }

        Card(Modifier.fillMaxWidth().padding(top = 10.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text("功率统计", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(6.dp))
                InfoRow("电池峰值 / 平均", "${fmtW(session.peakPowerW)} / ${fmtW(session.avgPowerW)}")
                InfoRow("输入峰值 / 平均", "${fmtW(session.peakInputW)} / ${fmtW(session.avgInputW)}")
                InfoRow("输入能量", fmtWh(session.inputEnergyWh))
                InfoRow("峰值电流", String.format(java.util.Locale.US, "%.2f A", session.peakCurrentA))
            }
        }

        Card(Modifier.fillMaxWidth().padding(top = 10.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text("温度统计", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(6.dp))
                InfoRow("峰值 / 平均温度", "${fmtC(session.peakTempC)} / ${fmtC(session.avgTempC)}")
            }
        }

        Spacer(Modifier.height(12.dp))
        ChartCard(
            title = "功率 / 时间",
            points = session.samples.toPoints { it.powerW.toFloat() },
            lineColor = Color(0xFF4CAF50),
            unit = "W",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        ChartCard(
            title = "电量 / 时间",
            points = session.samples.toPoints { it.capacity.toFloat() },
            lineColor = Color(0xFF2196F3),
            unit = "%",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        ChartCard(
            title = "温度 / 时间",
            points = session.samples.toPoints { it.tempC.toFloat() },
            lineColor = Color(0xFFFF9800),
            unit = "°",
            fmt = { String.format(java.util.Locale.US, "%.0f", it) },
        )
        Spacer(Modifier.height(20.dp))
    }
}
