package com.tunaneko.ui

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tunaneko.R
import com.tunaneko.state.VpnManager

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val logs by VpnManager.logs.collectAsState()

    var language by remember { mutableStateOf(VpnManager.language) }
    var autoRetry by remember { mutableStateOf(VpnManager.autoRetry) }
    var username by remember { mutableStateOf(VpnManager.defaultUsername) }
    var password by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
        Spacer(Modifier.height(12.dp))

        SettingsGroup(stringResource(R.string.settings_general)) {
            Text(stringResource(R.string.language), style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(6.dp))
            Row {
                listOf(
                    "auto" to stringResource(R.string.language_auto),
                    "ja" to "日本語", "en" to "English", "zh-Hans" to "中文"
                ).forEach { (code, label) ->
                    FilterChip(
                        selected = language == code,
                        onClick = {
                            language = code
                            VpnManager.language = code
                            (context as? android.app.Activity)?.recreate()
                        },
                        label = { Text(label, style = MaterialTheme.typography.labelSmall) },
                        modifier = Modifier.padding(end = 6.dp)
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(autoRetry, { autoRetry = it; VpnManager.autoRetry = it })
                Text(stringResource(R.string.auto_retry), style = MaterialTheme.typography.bodySmall)
            }
        }

        SettingsGroup(stringResource(R.string.default_credentials)) {
            OutlinedTextField(username, {
                username = it
                VpnManager.defaultUsername = it
            }, label = { Text(stringResource(R.string.username)) }, singleLine = true,
                modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.password)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Button(
                    enabled = password.isNotEmpty(),
                    onClick = {
                        VpnManager.credentialStore.setPassword("default", password)
                        password = ""
                        saved = true
                    },
                    shape = RoundedCornerShape(10.dp)
                ) { Text(stringResource(R.string.save)) }
                if (saved) {
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.saved), color = TunanekoColors.Green)
                }
            }
        }

        SettingsGroup(stringResource(R.string.about)) {
            Text("tunaneko", fontWeight = FontWeight.SemiBold)
            Text("v${com.tunaneko.BuildConfig.VERSION_NAME} / OpenConnect 9.21",
                style = MaterialTheme.typography.bodySmall, color = TunanekoColors.Gray)
        }

        SettingsGroup(stringResource(R.string.licenses)) {
            Text("tunaneko — MIT License", fontWeight = FontWeight.Medium)
            Text("OpenConnect 9.21 — LGPL v2.1", style = MaterialTheme.typography.bodySmall)
            Text("https://www.infradead.org/openconnect/", style = MaterialTheme.typography.labelSmall,
                color = TunanekoColors.Gray)
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.killswitch_note), style = MaterialTheme.typography.bodySmall,
                color = TunanekoColors.Gray)
            TextButton(onClick = { context.startActivity(Intent("android.settings.VPN_SETTINGS")) }) {
                Text(stringResource(R.string.open_vpn_settings))
            }
        }

        SettingsGroup(stringResource(R.string.log)) {
            Column(Modifier.heightIn(max = 200.dp).verticalScroll(rememberScrollState())) {
                logs.takeLast(80).forEach {
                    Text(it, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SettingsGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Text(title, style = MaterialTheme.typography.labelMedium, color = TunanekoColors.Gray,
        modifier = Modifier.padding(start = 4.dp, top = 12.dp, bottom = 6.dp))
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}
