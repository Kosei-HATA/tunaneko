package com.tunaneko.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.ShieldMoon
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tunaneko.R
import com.tunaneko.state.Status
import com.tunaneko.state.VpnManager

fun formatBytes(bytes: Long): String {
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var v = bytes.toDouble(); var u = 0
    while (v >= 1024 && u < units.size - 1) { v /= 1024; u++ }
    return "%.1f %s".format(v, units[u])
}

fun formatBps(bps: Double) = formatBytes(bps.toLong()) + "/s"

/**
 * Design blend: AnyConnect (dropdown + wide connect button),
 * Karing (2-col stat grid), Tunnelblick (status header), iOS (grouped cards).
 */
@Composable
fun HomeScreen(onConnect: () -> Unit, onDisconnect: () -> Unit, onGoServers: () -> Unit) {
    val status by VpnManager.status.collectAsState()
    val up by VpnManager.upBps.collectAsState()
    val down by VpnManager.downBps.collectAsState()
    val totUp by VpnManager.totalUp.collectAsState()
    val totDown by VpnManager.totalDown.collectAsState()
    val profiles by VpnManager.profiles.collectAsState()
    val selectedId by VpnManager.selectedId.collectAsState()
    val isMeasuring by VpnManager.isMeasuring.collectAsState()

    val busy = status is Status.Connecting || isMeasuring
    val connected = status is Status.Connected

    val accent by animateColorAsState(
        when {
            connected -> TunanekoColors.Green
            busy -> TunanekoColors.Orange
            status is Status.Failed -> TunanekoColors.Red
            else -> TunanekoColors.Blue
        }, label = "accent"
    )

    Column(
        Modifier.fillMaxSize().padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(24.dp))

        // ---- hero status card (Tunnelblick-ish, accent tinted) ----
        Card(
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = accent.copy(alpha = 0.10f)),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                Modifier.padding(18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(shape = CircleShape, color = accent.copy(alpha = 0.18f), modifier = Modifier.size(52.dp)) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            when (status) {
                                is Status.Connected -> Icons.Filled.CheckCircle
                                is Status.Failed -> Icons.Filled.Error
                                is Status.Connecting, Status.Measuring -> Icons.Filled.ShieldMoon
                                Status.Disconnected -> Icons.Filled.Shield
                            },
                            contentDescription = null,
                            tint = accent,
                            modifier = Modifier.size(30.dp)
                        )
                    }
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        when (status) {
                            is Status.Connected -> stringResource(R.string.status_connected)
                            is Status.Connecting -> stringResource(R.string.status_connecting)
                            is Status.Failed -> stringResource(R.string.status_failed)
                            Status.Disconnected -> stringResource(R.string.status_disconnected)
                            Status.Measuring -> stringResource(R.string.status_measuring)
                        },
                        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        when (val s = status) {
                            is Status.Connected -> "${s.profile.name} (${s.profile.host})"
                            is Status.Connecting -> "${s.profile.name} (${s.profile.host})"
                            is Status.Failed -> "${s.profileName} — ${s.reason}"
                            else -> ""
                        },
                        style = MaterialTheme.typography.bodySmall, color = TunanekoColors.Gray,
                        maxLines = 1
                    )
                }
            }
        }

        Spacer(Modifier.height(20.dp))

        // ---- server dropdown (AnyConnect-ish) ----
        ServerDropdown(
            profiles = profiles,
            selectedId = selectedId,
            enabled = !connected && !busy,
            onSelect = { VpnManager.select(it) },
            onManage = onGoServers
        )

        Spacer(Modifier.height(14.dp))

        // ---- wide connect button (AnyConnect-ish) ----
        Button(
            onClick = { if (connected || busy) onDisconnect() else onConnect() },
            enabled = !isMeasuring,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accent),
            modifier = Modifier.fillMaxWidth().height(52.dp)
        ) {
            if (busy) {
                CircularProgressIndicator(color = Color.White, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.status_connecting), color = Color.White)
            } else {
                Text(
                    stringResource(if (connected) R.string.disconnect else R.string.connect),
                    color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 16.sp
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        // ---- unified stats card (iOS grouped style) ----
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(Modifier.padding(vertical = 4.dp)) {
                StatRow(stringResource(R.string.uptime), uptimeText(status))
                StatDivider()
                StatRow(null, null) { SpeedLines(down, up, stringResource(R.string.speed)) }
                StatDivider()
                StatRow(null, null) { TrafficLines(totDown, totUp, stringResource(R.string.total_traffic)) }
                StatDivider()
                StatRow(
                    stringResource(R.string.current_profile),
                    when (val s = status) {
                        is Status.Connected -> s.profile.name
                        is Status.Connecting -> s.profile.name
                        else -> profiles.find { it.id == selectedId }?.name ?: stringResource(R.string.auto)
                    }
                )
            }
        }
    }
}

@Composable
private fun StatDivider() {
    HorizontalDivider(
        Modifier.padding(start = 16.dp),
        thickness = 0.5.dp,
        color = TunanekoColors.Gray.copy(alpha = 0.2f)
    )
}

@Composable
private fun StatRow(label: String?, value: String?, content: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (content != null) {
            content()
        } else {
            Text(label ?: "", style = MaterialTheme.typography.bodyMedium,
                color = TunanekoColors.Gray, modifier = Modifier.weight(1f))
            Text(value ?: "", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ServerDropdown(
    profiles: List<com.tunaneko.data.Profile>,
    selectedId: String?,
    enabled: Boolean,
    onSelect: (String?) -> Unit,
    onManage: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = profiles.find { it.id == selectedId }?.name ?: stringResource(R.string.auto)

    Card(
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth()
    ) {
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { if (enabled) expanded = it }) {
            OutlinedTextField(
                value = selectedName,
                onValueChange = {},
                readOnly = true,
                enabled = enabled,
                leadingIcon = { Icon(Icons.Filled.Bolt, null, tint = TunanekoColors.Orange) },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color.Transparent,
                    focusedBorderColor = Color.Transparent,
                    disabledBorderColor = Color.Transparent
                ),
                modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable)
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(
                    text = { Text("⚡ " + stringResource(R.string.auto)) },
                    onClick = { onSelect(null); expanded = false }
                )
                profiles.forEach { p ->
                    DropdownMenuItem(
                        text = { Text("${p.name}  (${p.host})") },
                        onClick = { onSelect(p.id); expanded = false }
                    )
                }
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.tab_servers) + "…") },
                    onClick = { expanded = false; onManage() }
                )
            }
        }
    }
}

@Composable
private fun SpeedLines(down: Double, up: Double, label: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = TunanekoColors.Gray,
            modifier = Modifier.weight(1f))
        Icon(Icons.Filled.ArrowDownward, null, tint = TunanekoColors.Blue, modifier = Modifier.size(14.dp))
        Text(formatBps(down), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        Spacer(Modifier.width(14.dp))
        Icon(Icons.Filled.ArrowUpward, null, tint = TunanekoColors.Green, modifier = Modifier.size(14.dp))
        Text(formatBps(up), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun TrafficLines(down: Long, up: Long, label: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = TunanekoColors.Gray,
            modifier = Modifier.weight(1f))
        Icon(Icons.Filled.ArrowDownward, null, tint = TunanekoColors.Blue, modifier = Modifier.size(14.dp))
        Text(formatBytes(down), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        Spacer(Modifier.width(14.dp))
        Icon(Icons.Filled.ArrowUpward, null, tint = TunanekoColors.Green, modifier = Modifier.size(14.dp))
        Text(formatBytes(up), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun uptimeText(status: Status): String {
    val connected = status as? Status.Connected ?: return "--:--"
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(connected.sinceMs) {
        while (true) {
            now = System.currentTimeMillis()
            kotlinx.coroutines.delay(1000)
        }
    }
    val s = ((now - connected.sinceMs) / 1000).toInt()
    return "%02d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
}
