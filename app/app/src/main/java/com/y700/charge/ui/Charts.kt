package com.y700.charge.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.y700.charge.data.ChargeSample

/** 电量环形仪表 */
@Composable
fun BatteryGauge(percent: Int, charging: Boolean, modifier: Modifier = Modifier) {
    val track = Color(0x22FFFFFF)
    val accent = if (charging) Color(0xFF4CAF50) else Color(0xFF2196F3)
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = size.minDimension * 0.11f
            val inset = stroke / 2f
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawArc(
                color = track,
                startAngle = 135f, sweepAngle = 270f, useCenter = false,
                topLeft = Offset(inset, inset), size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round)
            )
            drawArc(
                color = accent,
                startAngle = 135f,
                sweepAngle = 270f * (percent.coerceIn(0, 100) / 100f),
                useCenter = false,
                topLeft = Offset(inset, inset), size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round)
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$percent%", fontSize = 30.sp, fontWeight = FontWeight.Bold)
            Text(if (charging) "充电中" else "未充电", fontSize = 11.sp, color = accent)
        }
    }
}

/** 采样点 -> 折线图坐标 (x = 经过分钟数, y = 值) */
fun List<ChargeSample>.toPoints(sel: (ChargeSample) -> Float): List<Pair<Float, Float>> {
    if (isEmpty()) return emptyList()
    val t0 = first().t
    return map { ((it.t - t0) / 60_000f) to sel(it) }
}

/** 折线图卡片 */
@Composable
fun ChartCard(
    title: String,
    points: List<Pair<Float, Float>>,
    lineColor: Color,
    unit: String,
    fmt: (Float) -> String,
    modifier: Modifier = Modifier,
    emptyText: String = "暂无数据",
) {
    Card(modifier.fillMaxWidth().padding(vertical = 5.dp)) {
        Column(Modifier.padding(12.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            if (points.size < 2) {
                Box(Modifier.fillMaxWidth().height(110.dp), contentAlignment = Alignment.Center) {
                    Text(emptyText, fontSize = 12.sp, color = Color.Gray)
                }
            } else {
                val ys = points.map { it.second }
                val yMin = ys.min()
                val yMaxRaw = ys.max()
                val yMax = if (yMaxRaw - yMin < 0.5f) yMin + 1f else yMaxRaw
                val mid = (yMin + yMax) / 2f
                val xs = points.map { it.first }
                val xMin = xs.min()
                val xMax = xs.max()
                Row(Modifier.fillMaxWidth().height(125.dp)) {
                    Column(
                        Modifier.width(48.dp).fillMaxHeight(),
                        verticalArrangement = Arrangement.SpaceBetween,
                        horizontalAlignment = Alignment.End
                    ) {
                        Text(fmt(yMax) + unit, fontSize = 9.sp, color = Color.Gray)
                        Text(fmt(mid) + unit, fontSize = 9.sp, color = Color.Gray)
                        Text(fmt(yMin) + unit, fontSize = 9.sp, color = Color.Gray)
                    }
                    Spacer(Modifier.width(6.dp))
                    Canvas(Modifier.weight(1f).fillMaxHeight()) {
                        val w = size.width
                        val h = size.height
                        val xSpan = (xMax - xMin).coerceAtLeast(0.001f)
                        val ySpan = (yMax - yMin).coerceAtLeast(0.001f)
                        // 横向网格
                        for (i in 0..2) {
                            val yy = h * i / 2f
                            drawLine(Color(0x1AFFFFFF), Offset(0f, yy), Offset(w, yy), strokeWidth = 1f)
                        }
                        val path = Path()
                        points.forEachIndexed { i, p ->
                            val x = (p.first - xMin) / xSpan * w
                            val y = (1f - (p.second - yMin) / ySpan) * h
                            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                        }
                        drawPath(path, lineColor, style = Stroke(width = 2.2f, cap = StrokeCap.Round))
                    }
                }
                Row(Modifier.fillMaxWidth().padding(start = 54.dp, top = 2.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("${fmt(xMin)}分", fontSize = 9.sp, color = Color.Gray)
                    Text("${fmt(xMax)}分", fontSize = 9.sp, color = Color.Gray)
                }
            }
        }
    }
}
