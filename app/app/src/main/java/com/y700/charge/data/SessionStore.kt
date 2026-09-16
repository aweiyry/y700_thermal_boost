package com.y700.charge.data

import android.content.Context
import org.json.JSONArray
import java.io.File

/**
 * 会话持久化。
 *
 * 注意: 仅写入 App 私有目录 (filesDir), 与模块的充电日志 /sdcard/充电日志/ 完全独立,
 * 不会读取或修改模块日志文件。
 */
object SessionStore {

    private const val FILE_SESSIONS = "sessions.json"
    private const val FILE_CURRENT = "current_session.json"

    private fun sessionsFile(ctx: Context) = File(ctx.filesDir, FILE_SESSIONS)
    private fun currentFile(ctx: Context) = File(ctx.filesDir, FILE_CURRENT)

    fun loadSessions(ctx: Context): List<ChargeSession> {
        val f = sessionsFile(ctx)
        if (!f.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(f.readText())
            val list = ArrayList<ChargeSession>(arr.length())
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { list.add(ChargeSession.fromJson(it)) }
            }
            list.sortedByDescending { it.startTime }
        }.getOrDefault(emptyList())
    }

    fun saveSessions(ctx: Context, sessions: List<ChargeSession>) {
        runCatching {
            val arr = JSONArray()
            sessions.forEach { arr.put(it.toJson()) }
            sessionsFile(ctx).writeText(arr.toString())
        }
    }

    fun loadCurrent(ctx: Context): ChargeSession? {
        val f = currentFile(ctx)
        if (!f.exists()) return null
        return runCatching { ChargeSession.fromJson(org.json.JSONObject(f.readText())) }.getOrNull()
    }

    fun saveCurrent(ctx: Context, session: ChargeSession) {
        runCatching { currentFile(ctx).writeText(session.toJson().toString()) }
    }

    fun clearCurrent(ctx: Context) {
        runCatching { currentFile(ctx).delete() }
    }
}
