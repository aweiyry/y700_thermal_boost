package com.y700.charge.data

import android.content.Context
import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * 数据仓库: 轮询 /sys 读取实时数据 + 自动记录充电会话。
 *
 * 数据仅保存在 App 私有目录, 与模块的 /sdcard/充电日志/ 相互独立。
 */
object ChargeRepo {

    private const val SAMPLE_MS = 2_000L           // 每 2 秒记录一个采样点
    private const val PERSIST_EVERY_MS = 30_000L   // 进行中的会话每 30 秒落盘
    private const val LIVE_MAX = 3600              // 图表最多保留点数 (2s * 3600 = 2 小时)

    private lateinit var appCtx: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var started = false

    private var lastSampleAt = 0L
    private var lastPersistAt = 0L

    private val _live = MutableStateFlow(ChargeData())
    val live: StateFlow<ChargeData> = _live

    private val _rootState = MutableStateFlow("正在获取 root 权限…")
    val rootState: StateFlow<String> = _rootState

    private val _currentSamples = MutableStateFlow<List<ChargeSample>>(emptyList())
    val currentSamples: StateFlow<List<ChargeSample>> = _currentSamples

    private val _currentSession = MutableStateFlow<ChargeSession?>(null)
    val currentSession: StateFlow<ChargeSession?> = _currentSession

    private val _sessions = MutableStateFlow<List<ChargeSession>>(emptyList())
    val sessions: StateFlow<List<ChargeSession>> = _sessions

    fun init(ctx: Context) {
        if (started) return
        started = true
        appCtx = ctx.applicationContext
        _sessions.value = SessionStore.loadSessions(appCtx)
        SessionStore.loadCurrent(appCtx)?.let { c ->
            _currentSession.value = c
            _currentSamples.value = c.samples
        }
        scope.launch { loop() }
    }

    private suspend fun loop() {
        while (true) {
            val shell = runCatching { Shell.getShell() }.getOrNull()
            if (shell == null) {
                _rootState.value = "未获取 root 权限（请在授权框点『允许』）"
                delay(5_000)
                continue
            }
            _rootState.value = "root 已连接"
            val d = ChargeReader.read()
            if (d.readOk) {
                _live.value = d
                handleSession(d)
            }
            delay(1_000)
        }
    }

    private fun handleSession(d: ChargeData) {
        val now = System.currentTimeMillis()
        if (d.isCharging) {
            var cur = _currentSession.value
            if (cur == null) {
                cur = ChargeSession(
                    startTime = now,
                    endTime = now,
                    startCap = d.capacity,
                    endCap = d.capacity,
                    protocol = d.protocolLabel,
                    samples = emptyList(),
                    complete = false,
                )
                _currentSession.value = cur
                _currentSamples.value = emptyList()
                lastSampleAt = 0L
                lastPersistAt = now
            }
            if (now - lastSampleAt >= SAMPLE_MS) {
                val s = ChargeSample(
                    t = now,
                    powerW = d.batteryPowerW,
                    inputW = d.inputPowerW,
                    capacity = d.capacity,
                    tempC = d.batteryTempC,
                    currentA = kotlin.math.abs(d.batteryCurrentUa) / 1_000_000.0,
                    voltageV = d.batteryVoltageUv / 1_000_000.0,
                )
                val list = (cur.samples + s).takeLast(LIVE_MAX)
                cur = cur.copy(
                    endTime = now,
                    endCap = d.capacity,
                    protocol = if (d.protocolLabel != "未识别") d.protocolLabel else cur.protocol,
                    samples = list,
                )
                _currentSession.value = cur
                _currentSamples.value = list
                lastSampleAt = now
                if (now - lastPersistAt >= PERSIST_EVERY_MS) {
                    lastPersistAt = now
                    SessionStore.saveCurrent(appCtx, cur)
                }
            }
        } else {
            val cur = _currentSession.value
            if (cur != null) {
                val finished = cur.copy(endTime = now, endCap = d.capacity, complete = true)
                if (finished.samples.isNotEmpty()) {
                    val all = (_sessions.value + finished).sortedByDescending { it.startTime }
                    _sessions.value = all
                    SessionStore.saveSessions(appCtx, all)
                }
                SessionStore.clearCurrent(appCtx)
                _currentSession.value = null
                _currentSamples.value = emptyList()
                lastSampleAt = 0L
                lastPersistAt = 0L
            }
        }
    }

    fun deleteSession(startTime: Long) {
        val all = _sessions.value.filterNot { it.startTime == startTime }
        _sessions.value = all
        SessionStore.saveSessions(appCtx, all)
    }

    fun clearAllSessions() {
        _sessions.value = emptyList()
        SessionStore.saveSessions(appCtx, emptyList())
    }
}
