package com.tunaneko.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.tunaneko.R

/** First-launch onboarding: brand + 3-step guide. */
@Composable
fun OnboardingScreen(onStart: () -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(40.dp))

        // brand mark: white line fish on navy circle
        Surface(shape = CircleShape, color = TunanekoColors.Navy, modifier = Modifier.size(120.dp)) {
            Box(contentAlignment = Alignment.Center) {
                Image(
                    painter = painterResource(R.drawable.fish),
                    contentDescription = null,
                    modifier = Modifier.size(84.dp)
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        Text("tunaneko", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text(
            stringResource(R.string.onboarding_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = TunanekoColors.Gray,
            textAlign = TextAlign.Center
        )

        Spacer(Modifier.height(32.dp))

        OnboardingStep(Icons.Filled.Storage, stringResource(R.string.onboarding_step1))
        Spacer(Modifier.height(10.dp))
        OnboardingStep(Icons.Filled.Key, stringResource(R.string.onboarding_step2))
        Spacer(Modifier.height(10.dp))
        OnboardingStep(Icons.Filled.PowerSettingsNew, stringResource(R.string.onboarding_step3))

        Spacer(Modifier.height(28.dp))

        Button(
            onClick = onStart,
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth().height(52.dp)
        ) {
            Text(stringResource(R.string.onboarding_start), fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun OnboardingStep(icon: ImageVector, text: String) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Surface(
                shape = RoundedCornerShape(10.dp),
                color = TunanekoColors.Blue.copy(alpha = 0.12f),
                modifier = Modifier.size(40.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(icon, null, tint = TunanekoColors.Blue, modifier = Modifier.size(20.dp))
                }
            }
            Spacer(Modifier.width(14.dp))
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
