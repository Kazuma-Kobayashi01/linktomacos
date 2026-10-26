package com.linktomacos.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/**
 * 笔记本电脑和手机并排的示意图，全部用主题色画，跟随系统取色和深浅色。
 * [badges] 是浮在电脑屏幕上的几个功能图标（最多三个）。
 */
@Composable
fun HeroIllustration(badges: List<ImageVector>, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    BoxWithConstraints(modifier.aspectRatio(1.55f)) {
        val w = maxWidth
        val h = maxHeight
        Canvas(Modifier.fillMaxSize()) {
            val width = size.width
            val height = size.height
            // 笔记本屏幕和底座
            val screenTopLeft = Offset(width * 0.04f, height * 0.10f)
            val screenSize = Size(width * 0.72f, height * 0.64f)
            val corner = CornerRadius(height * 0.05f)
            drawRoundRect(
                brush = Brush.linearGradient(
                    listOf(colors.primary, colors.tertiary),
                    start = screenTopLeft,
                    end = Offset(screenTopLeft.x + screenSize.width, screenTopLeft.y + screenSize.height),
                ),
                topLeft = screenTopLeft, size = screenSize, cornerRadius = corner,
            )
            drawRoundRect(colors.surface, screenTopLeft, screenSize, corner, style = Stroke(height * 0.025f))
            drawRoundRect(
                colors.surface,
                topLeft = Offset(0f, height * 0.77f), size = Size(width * 0.80f, height * 0.05f),
                cornerRadius = CornerRadius(height * 0.025f),
            )
            // 手机：压在笔记本右侧
            val phoneTopLeft = Offset(width * 0.64f, height * 0.02f)
            val phoneSize = Size(width * 0.26f, height * 0.80f)
            val phoneCorner = CornerRadius(height * 0.07f)
            drawRoundRect(colors.inverseSurface, phoneTopLeft, phoneSize, phoneCorner)
            drawRoundRect(
                colors.surface, phoneTopLeft, phoneSize, phoneCorner, style = Stroke(height * 0.025f),
            )
            drawRoundRect(
                Brush.verticalGradient(listOf(colors.primary, colors.tertiary)),
                topLeft = Offset(phoneTopLeft.x + phoneSize.width * 0.12f, phoneTopLeft.y + phoneSize.height * 0.07f),
                size = Size(phoneSize.width * 0.76f, phoneSize.height * 0.86f),
                cornerRadius = CornerRadius(height * 0.04f),
            )
        }
        // 浮在屏幕上的功能图标卡片
        val card = h * 0.2f
        badges.take(3).forEachIndexed { index, icon ->
            Surface(
                modifier = Modifier
                    .size(card)
                    .offset(x = w * 0.09f + (card + w * 0.025f) * index, y = h * 0.36f)
                    .align(Alignment.TopStart),
                shape = RoundedCornerShape(card * 0.28f),
                color = colors.surface,
                shadowElevation = 3.dp,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(icon, contentDescription = null, tint = colors.primary, modifier = Modifier.size(card * 0.56f))
                }
            }
        }
    }
}
