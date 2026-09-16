package com.y700.charge

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.topjohnwu.superuser.Shell
import com.y700.charge.data.ChargeData
import com.y700.charge.data.ChargeReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    ChargeScreen()
                }
            }
        }
    }
}

@Composable
fun ChargeScreen() {
    var data by remember { mutableStateOf<ChargeData?>(null) }
    var rootState by remember { mutableStateOf("正在获取 root 权限…") }

    LaunchedEffect(Unit) {
        val shell = withContext(Dispatchers.IO) { runCatching { Shell.getShell() }.getOrNull() }
        if (shell == null) {
            rootState = "未获取 root 权限（需 KernelSU/Magisk 授权）"
            return@LaunchedEffect
        }
        rootState = "root 已连接"
        while (true) {
            data = withContext(Dispatchers.IO) { ChargeReader.read() }
            delay(1000)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text("Y700 充电监控", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(
            "模块 ${data?.moduleVersion ?: "—"} · ${if (data?.moduleRunning == true) "运行中" else "未运行"} · $rootState",
            fontSize = 12.sp,
            color = Color.Gray
        )
        Spacer(Modifier.height(16.dp))

        val d = data
        if (d == null || !d.readOk) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("等待数据…", fontSize = 16.sp)
                    Text(rootState, fontSize = 13.sp, color = Color.Gray)
                }
            }
        } else {
            SectionCard("充电状态") {
                InfoRow("状态", if (d.isCharging) "充电中" else d.status.ifBlank { "—" })
                InfoRow("充电协议", d.protocolLabel)
                InfoRow("充电类型", d.chargeType.ifBlank { "—" })
                InfoRow("电量", "${d.capacity}%")
            }
            SectionCard("电池") {
                InfoRow("电流", fmtA(kotlin.math.abs(d.batteryCurrentUa)))
                InfoRow("电压", fmtV(d.batteryVoltageUv))
                InfoRow("功率", fmtW(d.batteryPowerW))
                InfoRow("温度", String.format(Locale.US, "%.1f °C", d.batteryTempC))
                InfoRow("充电电流上限", if (d.cclMax > 0) "${fmtA(d.ccl)} / ${fmtA(d.cclMax)}" else "—")
            }
            SectionCard("输入 (充电器)") {
                InfoRow("输入电压", fmtV(d.inputVoltageUv))
                InfoRow("输入电流", fmtA(kotlin.math.abs(d.inputCurrentUa)))
                InfoRow("输入功率", fmtW(d.inputPowerW))
                InfoRow("输入电流上限", if (d.inputLimitUa > 0) fmtA(d.inputLimitUa) else "—")
            }
        }
    }
}

@Composable
fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            content()
        }
    }
}

@Composable
fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 14.sp, color = Color.Gray)
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Medium)
    }
}

private fun fmtA(ua: Long): String = String.format(Locale.US, "%.2f A", ua / 1_000_000.0)
private fun fmtV(uv: Long): String = String.format(Locale.US, "%.3f V", uv / 1_000_000.0)
private fun fmtW(w: Double): String = String.format(Locale.US, "%.1f W", w)
