package com.focusguard.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.focusguard.ui.theme.FocusGuardColors

@Composable
fun AttentionBudgetRingCard(
    usedMinutes: Int,
    totalMinutes: Int,
    categoryName: String = "Entertainment Budget"
) {
    val fraction = if (totalMinutes > 0) (usedMinutes.toFloat() / totalMinutes.toFloat()).coerceIn(0f, 1f) else 0f
    val remainingMinutes = (totalMinutes - usedMinutes).coerceAtLeast(0)

    val statusColor = when {
        fraction >= 1.0f -> FocusGuardTheme.Danger
        fraction >= 0.8f -> FocusGuardTheme.Warning
        else -> FocusGuardTheme.Accent
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(FocusGuardTheme.Surface, RoundedCornerShape(16.dp))
            .border(1.dp, FocusGuardTheme.Border, RoundedCornerShape(16.dp))
            .padding(20.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Canvas Circular Ring Progress
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(100.dp)
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val strokeWidth = 10.dp.toPx()

                    drawCircle(
                        color = FocusGuardTheme.Border,
                        style = Stroke(width = strokeWidth)
                    )

                    drawArc(
                        brush = Brush.sweepGradient(
                            colors = listOf(statusColor, FocusGuardTheme.Violet, statusColor)
                        ),
                        startAngle = -90f,
                        sweepAngle = fraction * 360f,
                        useCenter = false,
                        style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                    )
                }

                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "${(fraction * 100).toInt()}%",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = FocusGuardTheme.TextPrimary
                    )
                    Text(
                        text = "consumed",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = FocusGuardTheme.TextMuted
                    )
                }
            }

            // Numeric Metrics
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "ATTENTION BUDGET • $categoryName",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = FocusGuardTheme.TextSecondary
                )

                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = "$usedMinutes",
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                    Text(
                        text = " / $totalMinutes min",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = FocusGuardTheme.TextSecondary,
                        modifier = Modifier.padding(bottom = 2.dp, start = 4.dp)
                    )
                }

                Box(
                    modifier = Modifier
                        .background(statusColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = if (remainingMinutes == 0) "Budget exhausted" else "$remainingMinutes m remaining today",
                        fontSize = 12.sp,
                        color = if (remainingMinutes == 0) FocusGuardTheme.Danger else FocusGuardTheme.TextSecondary,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}
