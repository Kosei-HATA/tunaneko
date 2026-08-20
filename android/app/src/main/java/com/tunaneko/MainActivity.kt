package com.tunaneko

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.tunaneko.state.VpnManager
import com.tunaneko.ui.HomeScreen
import com.tunaneko.ui.OnboardingScreen
import com.tunaneko.ui.ServersScreen
import com.tunaneko.ui.SettingsScreen
import com.tunaneko.ui.TunanekoTheme

class MainActivity : ComponentActivity() {

    override fun attachBaseContext(newBase: android.content.Context) {
        // manual in-app locale: AppCompatDelegate.setApplicationLocales is
        // unreliable without AppCompatActivity, so apply it at context creation
        val lang = newBase.getSharedPreferences("settings", MODE_PRIVATE)
            .getString("language", "auto") ?: "auto"
        if (lang == "auto") {
            super.attachBaseContext(newBase)
        } else {
            val config = android.content.res.Configuration(newBase.resources.configuration)
            config.setLocale(java.util.Locale.forLanguageTag(lang))
            super.attachBaseContext(newBase.createConfigurationContext(config))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        VpnManager.init(this)
        requestNotificationPermission()
        setContent {
            TunanekoTheme { AppRoot() }
        }
    }

    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    @Composable
    fun AppRoot() {
        var tab by remember { mutableIntStateOf(0) }
        val prefs = remember { getSharedPreferences("settings", MODE_PRIVATE) }
        var showOnboarding by remember { mutableStateOf(prefs.getString("onboardingDone", null) == null) }

        if (showOnboarding) {
            OnboardingScreen(onStart = {
                prefs.edit().putString("onboardingDone", "1").apply()
                showOnboarding = false
            })
            return
        }

        val vpnPrepare = rememberLauncherForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == RESULT_OK) {
                VpnManager.connect(this)
            }
        }

        Scaffold(
            bottomBar = {
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surface,
                    tonalElevation = 0.dp
                ) {
                    NavigationBarItem(
                        selected = tab == 0, onClick = { tab = 0 },
                        icon = { Icon(Icons.Filled.Home, null) },
                        label = { Text(stringResource(R.string.tab_home)) }
                    )
                    NavigationBarItem(
                        selected = tab == 1, onClick = { tab = 1 },
                        icon = { Icon(Icons.Filled.Storage, null) },
                        label = { Text(stringResource(R.string.tab_servers)) }
                    )
                    NavigationBarItem(
                        selected = tab == 2, onClick = { tab = 2 },
                        icon = { Icon(Icons.Filled.Settings, null) },
                        label = { Text(stringResource(R.string.tab_settings)) }
                    )
                }
            }
        ) { padding ->
            Box(Modifier.padding(padding)) {
                when (tab) {
                    0 -> HomeScreen(
                        onConnect = {
                            val prep = VpnService.prepare(this@MainActivity)
                            if (prep != null) vpnPrepare.launch(prep) else VpnManager.connect(this@MainActivity)
                        },
                        onDisconnect = { VpnManager.disconnect(this@MainActivity) },
                        onGoServers = { tab = 1 }
                    )
                    1 -> ServersScreen()
                    2 -> SettingsScreen()
                }
            }
        }
    }
}
