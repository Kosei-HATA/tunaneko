package com.tunaneko.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tunaneko.R
import com.tunaneko.data.IpType
import com.tunaneko.data.Profile
import com.tunaneko.state.VpnManager

@Composable
fun ServersScreen() {
    val profiles by VpnManager.profiles.collectAsState()
    val selectedId by VpnManager.selectedId.collectAsState()
    val isMeasuring by VpnManager.isMeasuring.collectAsState()
    val context = LocalContext.current

    var search by remember { mutableStateOf("") }
    var sortByLatency by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Profile?>(null) }
    var showAdd by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<Profile?>(null) }

    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let {
            context.contentResolver.openInputStream(it)?.use { stream ->
                val text = stream.readBytes().decodeToString()
                val imported = if (text.trimStart().startsWith("[")) {
                    try {
                        Profile.listFromJson(text).map { p ->
                            // new id: credentials/pins don't carry over
                            p.copy(id = java.util.UUID.randomUUID().toString(), hasOwnPassword = false)
                        }
                    } catch (e: Exception) {
                        VpnManager.log("import failed: invalid JSON")
                        emptyList()
                    }
                } else Profile.listFromText(text)
                imported.forEach(VpnManager::addOrUpdate)
                VpnManager.log("imported ${imported.size} server(s)")
            }
        }
    }
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        uri?.let {
            context.contentResolver.openOutputStream(it)?.use { stream ->
                stream.write(Profile.listToJson(profiles).toByteArray())
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        Spacer(Modifier.height(12.dp))

        // search + actions
        OutlinedTextField(
            search, { search = it },
            placeholder = { Text(stringResource(R.string.search)) },
            leadingIcon = { Icon(Icons.Filled.Search, null, tint = TunanekoColors.Gray) },
            shape = RoundedCornerShape(12.dp),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Row(
            Modifier.fillMaxWidth().padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = { VpnManager.measureAll() }, enabled = !isMeasuring) {
                Icon(Icons.Filled.Speed, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (isMeasuring) stringResource(R.string.status_measuring) else stringResource(R.string.measure_all))
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { showAdd = true }) { Icon(Icons.Filled.Add, null, tint = TunanekoColors.Blue) }
            IconButton(onClick = { importLauncher.launch(arrayOf("*/*")) }) {
                Icon(Icons.Filled.FileDownload, null, tint = TunanekoColors.Blue)
            }
            IconButton(onClick = { exportLauncher.launch("tunaneko-servers.json") }) {
                Icon(Icons.Filled.FileUpload, null, tint = TunanekoColors.Blue)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(sortByLatency, { sortByLatency = it })
            Text(stringResource(R.string.sort_latency), style = MaterialTheme.typography.bodySmall)
        }

        // auto row
        ServerRow(
            title = stringResource(R.string.auto),
            subtitle = stringResource(R.string.auto_desc),
            selected = selectedId == null,
            latencyMs = null,
            isAuto = true,
            onClick = { VpnManager.select(null) },
            onEdit = null,
            onDelete = null
        )

        val filtered = profiles
            .filter { search.isEmpty() || it.name.contains(search, true) || it.host.contains(search, true) }
            .let { if (sortByLatency) it.sortedBy { p -> p.latencyMs ?: Int.MAX_VALUE } else it }

        LazyColumn {
            items(filtered, key = { it.id }) { p ->
                ServerRow(
                    title = p.name,
                    subtitle = p.host,
                    selected = selectedId == p.id,
                    latencyMs = p.latencyMs,
                    isAuto = false,
                    onClick = { VpnManager.select(p.id) },
                    onEdit = { editing = p },
                    onDelete = { deleteTarget = p }
                )
            }
        }
    }

    editing?.let { ProfileEditDialog(profile = it, onDismiss = { editing = null }) }
    if (showAdd) ProfileEditDialog(profile = null, onDismiss = { showAdd = false })
    deleteTarget?.let { p ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_body, p.name, p.host)) },
            confirmButton = {
                TextButton(onClick = { VpnManager.delete(p); deleteTarget = null }) {
                    Text(stringResource(R.string.delete_server), color = TunanekoColors.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

@Composable
private fun ServerRow(
    title: String, subtitle: String, selected: Boolean, latencyMs: Int?,
    isAuto: Boolean, onClick: () -> Unit, onEdit: (() -> Unit)?, onDelete: (() -> Unit)?
) {
    Card(
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) TunanekoColors.Blue.copy(alpha = 0.08f)
            else MaterialTheme.colorScheme.surface
        ),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable(onClick = onClick)
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            // selection indicator
            Surface(
                shape = CircleShape,
                color = if (selected) TunanekoColors.Blue else Color.Transparent,
                border = if (selected) null else androidx.compose.foundation.BorderStroke(1.5.dp, TunanekoColors.Gray),
                modifier = Modifier.size(22.dp)
            ) {
                if (selected) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.padding(3.dp))
            }
            Spacer(Modifier.width(12.dp))
            if (isAuto) {
                Icon(Icons.Filled.Bolt, null, tint = TunanekoColors.Orange, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Medium)
                Text(subtitle, style = MaterialTheme.typography.labelSmall, color = TunanekoColors.Gray)
            }
            if (latencyMs != null) {
                LatencyBadge(latencyMs)
            }
            onEdit?.let { IconButton(onClick = it) { Icon(Icons.Filled.Edit, null, tint = TunanekoColors.Gray, modifier = Modifier.size(18.dp)) } }
            onDelete?.let { IconButton(onClick = it) { Icon(Icons.Filled.DeleteOutline, null, tint = TunanekoColors.Red, modifier = Modifier.size(18.dp)) } }
        }
    }
}

@Composable
private fun LatencyBadge(ms: Int) {
    val color = when {
        ms < 80 -> TunanekoColors.Green
        ms < 200 -> TunanekoColors.Orange
        else -> TunanekoColors.Red
    }
    Surface(shape = RoundedCornerShape(8.dp), color = color.copy(alpha = 0.12f)) {
        Text("$ms ms", style = MaterialTheme.typography.labelSmall, color = color,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp))
    }
}

@Composable
fun ProfileEditDialog(profile: Profile?, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf(profile?.name ?: "") }
    var host by remember { mutableStateOf(profile?.host ?: "") }
    var proto by remember { mutableStateOf(profile?.protocol ?: "anyconnect") }
    var ipType by remember { mutableStateOf(profile?.ipType ?: IpType.IPV4) }
    var ownCreds by remember { mutableStateOf(profile?.username != null || profile?.hasOwnPassword == true) }
    var username by remember { mutableStateOf(profile?.username ?: "") }
    var password by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        shape = RoundedCornerShape(20.dp),
        title = { Text(profile?.name ?: stringResource(R.string.add_server), fontWeight = FontWeight.SemiBold) },
        text = {
            Column {
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.profile_name)) }, singleLine = true)
                Spacer(Modifier.height(6.dp))
                OutlinedTextField(host, {
                    host = it
                    ipType = IpType.of(it)
                }, label = { Text(stringResource(R.string.profile_host)) }, singleLine = true)
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(ipType == IpType.IPV4, { ipType = IpType.IPV4 }, label = { Text("IPv4") })
                    Spacer(Modifier.width(8.dp))
                    FilterChip(ipType == IpType.IPV6, { ipType = IpType.IPV6 }, label = { Text("IPv6") })
                }
                run {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(ownCreds, { ownCreds = it })
                        Text(stringResource(R.string.own_credentials), style = MaterialTheme.typography.bodySmall)
                    }
                    if (ownCreds) {
                        OutlinedTextField(username, { username = it }, label = { Text(stringResource(R.string.username)) }, singleLine = true)
                        Spacer(Modifier.height(6.dp))
                        OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.password)) }, singleLine = true)
                    } else {
                        Text(stringResource(R.string.using_default), style = MaterialTheme.typography.labelSmall,
                            color = TunanekoColors.Gray)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = name.isNotEmpty() && host.isNotEmpty(),
                onClick = {
                    val p = (profile ?: Profile(name = name, host = host)).copy(
                        name = name, host = host, protocol = proto, ipType = ipType
                    )
                    if (ownCreds) {
                        p.username = username.ifEmpty { null }
                        if (password.isNotEmpty()) {
                            VpnManager.credentialStore.setPassword(p.id, password)
                            p.hasOwnPassword = true
                        }
                    } else {
                        p.username = null
                        VpnManager.credentialStore.delete(p.id)
                        p.hasOwnPassword = false
                    }
                    VpnManager.addOrUpdate(p)
                    onDismiss()
                }
            ) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        }
    )
}
