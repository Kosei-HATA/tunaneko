package com.tunaneko.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS-inspired palette
object TunanekoColors {
    val Blue = Color(0xFF0A84FF)
    val Green = Color(0xFF30D158)
    val Orange = Color(0xFFFF9F0A)
    val Red = Color(0xFFFF453A)
    val Gray = Color(0xFF8E8E93)
    val Navy = Color(0xFF121D30)
    val LightBg = Color(0xFFF2F2F7)
    val LightCard = Color.White
    val DarkBg = Color(0xFF000000)
    val DarkCard = Color(0xFF1C1C1E)
}

private val LightColors = lightColorScheme(
    primary = TunanekoColors.Blue,
    background = TunanekoColors.LightBg,
    surface = TunanekoColors.LightCard,
    surfaceVariant = TunanekoColors.LightBg,
    error = TunanekoColors.Red
)

private val DarkColors = darkColorScheme(
    primary = TunanekoColors.Blue,
    background = TunanekoColors.DarkBg,
    surface = TunanekoColors.DarkCard,
    surfaceVariant = TunanekoColors.DarkCard,
    error = TunanekoColors.Red
)

@Composable
fun TunanekoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
