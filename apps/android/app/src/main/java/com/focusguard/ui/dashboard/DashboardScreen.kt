package com.focusguard.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.focusguard.ui.components.AppUsageModel
import com.focusguard.ui.components.ApplicationCardRow
import com.focusguard.ui.components.AttentionBudgetRingCard
import com.focusguard.ui.theme.FocusGuardColors
import com.focusguard.ui.theme.FocusGuardTheme
import kotlinx.coroutines.delay

@Composable
fun DashboardScreen() {
    FocusGuardTheme {
        var isFocusActive by remember { mutableStateOf(false) }
        var focusRemainingSeconds by remember { mutableStateOf(2700) } // 45m

        LaunchedEffect(isFocusActive, focusRemainingSeconds) {
            if (isFocusActive && focusRemainingSeconds > 0) {
                delay(1000L)
                focusRemainingSeconds -= 1
            } else if (focusRemainingSeconds == 0) {
                isFocusActive = false
            }
        }

        val topApps = listOf(
            AppUsageModel("YouTube", 28, 30, Color(0xFFEF4444)),
            AppUsageModel("Instagram", 17, 20, Color(0xFF8B5CF6)),
            AppUsageModel("Browser", 41, 60, Color(0xFF3B82F6))
        )

        val devices = listOf(
            Pair("MacBook Pro", "Synced 12s ago"),
            Pair("Pixel 8", "Synced 24s ago")
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(FocusGuardColors.Background)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "FOCUSGUARD",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = FocusGuardColors.Accent
                        )
                        Text(
                            text = "•",
                            color = FocusGuardColors.TextMuted
                        )
                        Text(
                            text = "Good evening",
                            fontSize = 12.sp,
                            color = FocusGuardColors.TextSecondary
                        )
                    }

                    Text(
                        text = "Your attention today",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        color = FocusGuardColors.TextPrimary
                    )
                }

                Surface(
                    shape = RoundedCornerShape(20.dp),
                    color = FocusGuardColors.SurfaceElevated
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(FocusGuardColors.Success)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "Protected",
                            fontSize = 12.sp,
                            color = FocusGuardColors.TextPrimary,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            // Attention Budget Ring Hero Card
            AttentionBudgetRingCard(usedMinutes = 71, totalMinutes = 90)

            // Applications Section
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "Top Applications",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = FocusGuardColors.TextPrimary
                )

                topApps.forEach { app ->
                    ApplicationCardRow(item = app)
                }
            }

            // Focus Mode Session Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = FocusGuardColors.Surface),
                border = androidx.compose.foundation.BorderStroke(1.dp, FocusGuardColors.Border)
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    if (isFocusActive) {
                        Text(
                            text = "FOCUS SESSION ACTIVE",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = FocusGuardColors.Accent
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = formatSeconds(focusRemainingSeconds),
                            fontSize = 42.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = FocusGuardColors.TextPrimary
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Protected • Distractions shielded",
                            fontSize = 12.sp,
                            color = FocusGuardColors.Success
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Button(
                            onClick = { isFocusActive = false },
                            colors = ButtonDefaults.buttonColors(containerColor = FocusGuardColors.Danger.copy(alpha = 0.2f)),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = "End Focus Session",
                                fontSize = 14.sp,
                                color = FocusGuardColors.Danger,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    } else {
                        Button(
                            onClick = {
                                isFocusActive = true
                                focusRemainingSeconds = 2700
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(52.dp)
                                .background(
                                    brush = Brush.horizontalGradient(
                                        colors = listOf(FocusGuardColors.Accent, FocusGuardColors.Indigo)
                                    ),
                                    shape = RoundedCornerShape(12.dp)
                                ),
                            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text(
                                text = "START 45M FOCUS SESSION",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }
            }

            // Enrolled Devices Section
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = FocusGuardColors.Surface),
                border = androidx.compose.foundation.BorderStroke(1.dp, FocusGuardColors.Border)
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Enrolled Devices",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = FocusGuardColors.TextPrimary
                    )

                    devices.forEach { (name, status) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(FocusGuardColors.SurfaceElevated, RoundedCornerShape(10.dp))
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(
                                    text = name,
                                    fontSize = 14.sp,
                                    color = FocusGuardColors.TextPrimary,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = status,
                                    fontSize = 11.sp,
                                    color = FocusGuardColors.TextSecondary
                                )
                            }
                            Surface(
                                shape = RoundedCornerShape(6.dp),
                                color = FocusGuardColors.Success.copy(alpha = 0.12f)
                            ) {
                                Text(
                                    text = "Protected",
                                    fontSize = 11.sp,
                                    color = FocusGuardColors.Success,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun formatSeconds(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return String.format("%02d:%02d", m, s)
}
