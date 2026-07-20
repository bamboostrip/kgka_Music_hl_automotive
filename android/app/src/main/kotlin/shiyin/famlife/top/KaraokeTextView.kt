package shiyin.famlife.top

import android.content.Context
import kotlin.math.abs
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View

/**
 * Custom view that renders lyrics with a karaoke-style horizontal fill effect.
 * The text is drawn in a dim base color, then an active portion is drawn in a
 * bright color, clipped to the current progress width.
 */
class KaraokeTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        isFakeBoldText = true
    }

    private val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        isFakeBoldText = true
    }

    private val clipRect = RectF()

    var text: String = ""
        set(value) {
            if (field != value) {
                field = value
                requestLayout()
                invalidate()
            }
        }

    var baseColor: Int = Color.argb(90, 255, 255, 255)
        set(value) {
            field = value
            basePaint.color = value
            invalidate()
        }

    var activeColor: Int = Color.WHITE
        set(value) {
            field = value
            activePaint.color = value
            invalidate()
        }

    var textSizeSp: Float = 16f
        set(value) {
            field = value
            val px = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics
            )
            basePaint.textSize = px
            activePaint.textSize = px
            requestLayout()
            invalidate()
        }

    /** Progress from 0.0 (nothing highlighted) to 1.0 (fully highlighted). */
    var progress: Float = 0f
        set(value) {
            val clamped = value.coerceIn(0f, 1f)
            if (abs(field - clamped) > 0.001f) {
                field = clamped
                invalidate()
            }
        }

    var maxLines: Int = 2

    init {
        val px = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, textSizeSp, resources.displayMetrics
        )
        basePaint.textSize = px
        activePaint.textSize = px
        basePaint.color = baseColor
        activePaint.color = activeColor
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)

        val width = when (widthMode) {
            MeasureSpec.EXACTLY -> widthSize
            MeasureSpec.AT_MOST -> {
                val textWidth = if (text.isEmpty()) 0f
                else basePaint.measureText(text).coerceAtMost(widthSize.toFloat())
                (textWidth + paddingLeft + paddingRight).toInt().coerceAtMost(widthSize)
            }
            else -> {
                val textWidth = if (text.isEmpty()) 0f else basePaint.measureText(text)
                (textWidth + paddingLeft + paddingRight).toInt()
            }
        }

        val lineHeight = basePaint.fontMetrics.let { it.bottom - it.top + it.leading }
        val textHeight = (lineHeight * maxLines.coerceAtLeast(1))
        val height = (textHeight + paddingTop + paddingBottom).toInt()

        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (text.isEmpty()) return

        val x = paddingLeft.toFloat()
        val y = paddingTop - basePaint.fontMetrics.top

        // Draw base (dim) text
        canvas.drawText(text, x, y, basePaint)

        // Draw active (bright) text clipped to progress
        if (progress > 0f) {
            val totalWidth = basePaint.measureText(text)
            val clipWidth = totalWidth * progress
            clipRect.set(
                x,
                0f,
                x + clipWidth,
                height.toFloat()
            )
            canvas.save()
            canvas.clipRect(clipRect)
            canvas.drawText(text, x, y, activePaint)
            canvas.restore()
        }
    }
}
