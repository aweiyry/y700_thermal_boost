package com.y700.charge

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.y700.charge.data.ChargeRepo
import com.y700.charge.data.ChargeSession
import com.y700.charge.ui.HistoryScreen
import com.y700.charge.ui.RealtimeScreen
import com.y700.charge.ui.SessionDetailScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ChargeRepo.init(applicationContext)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    AppRoot()
                }
            }
        }
    }
}

sealed interface Route {
    data object Live : Route
    data object History : Route
    data class Detail(val session: ChargeSession) : Route
}

@Composable
fun AppRoot() {
    val live by ChargeRepo.live.collectAsState()
    val rootState by ChargeRepo.rootState.collectAsState()
    val samples by ChargeRepo.currentSamples.collectAsState()
    val session by ChargeRepo.currentSession.collectAsState()
    val sessions by ChargeRepo.sessions.collectAsState()

    var route by remember { mutableStateOf<Route>(Route.Live) }

    when (val r = route) {
        is Route.Live -> RealtimeScreen(
            data = live,
            rootState = rootState,
            samples = samples,
            session = session,
            sessionCount = sessions.size,
            onOpenHistory = { route = Route.History },
        )

        is Route.History -> HistoryScreen(
            sessions = sessions,
            onBack = { route = Route.Live },
            onOpen = { route = Route.Detail(it) },
            onDelete = { ChargeRepo.deleteSession(it) },
            onClearAll = { ChargeRepo.clearAllSessions() },
        )

        is Route.Detail -> {
            val shown = sessions.firstOrNull { it.startTime == r.session.startTime } ?: r.session
            SessionDetailScreen(session = shown, onBack = { route = Route.History })
        }
    }
}
