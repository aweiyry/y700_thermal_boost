package com.y700.charge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val TIME_FMT = DateTimeFormatter.ofPattern("HH:mm:ss")
private val DATE_FMT = DateTimeFormatter.ofPattern("MM-dd HH:mm")
private val FULL_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

@Composable
fun InfoRow(label: String, value: String, valueColor: Color? = null) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, fontSize = 13.sp, color = Color.Gray)
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = valueColor ?: Color.Unspecified)
    }
}

fun fmtA(ua: Long): String = String.format(Locale.US, "%.2f A", kotlin.math.abs(ua) / 1_000_000.0)
fun fmtV(uv: Long): String = String.format(Locale.US, "%.3f V", uv / 1_000_000.0)
fun fmtW(w: Double): String = String.format(Locale.US, "%.2f W", w)
fun fmtC(c: Double): String = String.format(Locale.US, "%.1f °C", c)
fun fmtWh(wh: Double): String = String.format(Locale.US, "%.2f Wh", wh)

fun fmtClock(ms: Long): String =
    Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(TIME_FMT)

fun fmtDate(ms: Long): String =
    Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(DATE_FMT)

fun fmtFull(ms: Long): String =
    Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(FULL_FMT)

fun fmtDuration(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "${h}h${m}m" else if (m > 0) "${m}m${s}s" else "${s}s"
}
