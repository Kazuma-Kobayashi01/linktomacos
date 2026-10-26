package com.linktomacos.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/**
 * 应用自带的线性图标（24×24，描边 1.8，圆头圆角），统一风格，不依赖庞大的 material-icons-extended。
 * 路径用 SVG 的 d 语法写。
 */
object LinkIcons {
    val Bell = icon("Bell", "M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15z", "M10 20.5a2 2 0 0 0 4 0")
    val Moon = icon("Moon", "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z")
    val Clipboard = icon(
        "Clipboard",
        "M9 3.5h6a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-.5.5H9a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z",
        "M15.5 5h1.5a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h1.5",
        "M9 12h6", "M9 16h4",
    )
    val Monitor = icon("Monitor", "M5 4.5h14A2 2 0 0 1 21 6.5v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2z", "M8.5 20h7", "M12 16.5V20")
    val Folder = icon("Folder", "M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2.5h8.5A1.5 1.5 0 0 1 21 9v9.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z")
    val Phone = icon("Phone", "M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M11 18h2")
    val Laptop = icon("Laptop", "M5 6.5A1.5 1.5 0 0 1 6.5 5h11A1.5 1.5 0 0 1 19 6.5V15H5z", "M2.5 18.5h19")
    val ChevronRight = icon("ChevronRight", "M9.5 6l6 6-6 6")
    val ArrowBack = icon("ArrowBack", "M19 12H5", "M11 6l-6 6 6 6")
    val Bolt = icon("Bolt", "M13 3L5 13.5h6L10 21l8-10.5h-6z")
    val Check = icon("Check", "M5 12.5l4.5 4.5L19 7.5")
    val Warning = icon("Warning", "M12 4L2.5 20h19z", "M12 10v4.5", "M12 17.5v.01")
    val Link = icon(
        "Link",
        "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1",
        "M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
    )
    val MoreVert = icon("MoreVert", "M12 5v.01", "M12 12v.01", "M12 19v.01", width = 2.6f)
    val Info = icon("Info", "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z", "M12 11v5", "M12 8v.01")
    val QrCode = icon(
        "QrCode",
        "M4 4h6v6H4z", "M14 4h6v6h-6z", "M4 14h6v6H4z",
        "M14 14h2.5v2.5H14z", "M20 14v.01", "M14 20v.01", "M17 20h3v-3",
    )
    val Shield = icon("Shield", "M12 3l7 3v5c0 4.5-3 8.5-7 10-4-1.5-7-5.5-7-10V6z")
    val Phone2Mac = icon("Phone2Mac", "M3 7a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z", "M7 19.5h4", "M17.5 9h2A1.5 1.5 0 0 1 21 10.5v8a1.5 1.5 0 0 1-1.5 1.5h-2A1.5 1.5 0 0 1 16 18.5v-8A1.5 1.5 0 0 1 17.5 9z")

    private fun icon(name: String, vararg paths: String, width: Float = 1.8f): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            for (d in paths) {
                addPath(
                    pathData = PathParser().parsePathString(d).toNodes(),
                    stroke = SolidColor(Color.Black),
                    strokeLineWidth = width,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()
}
