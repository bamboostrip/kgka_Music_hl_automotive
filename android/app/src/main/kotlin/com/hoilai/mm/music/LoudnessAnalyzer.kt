package com.hoilai.mm.music

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.pow

/**
 * EBU R128 / ITU-R BS.1770-4 integrated loudness(LUFS)分析器。
 *
 * 完整流程:解码为 PCM → 每通道独立 K-weighting(固定系数表,48k/44.1k 精确)
 * → 400ms 滑动窗(100ms hop)分块 → 两轮门限(absolute -70 LUFS + relative -10 LU)
 * → gated integrated loudness。
 *
 * K-weighting 用 EBU TECH 3321 标准固定系数表(48k/44.1k 精确,其它采样率
 * 取最接近者)。避免手写系数重算公式带来的数值稳定性问题。
 *
 * 仅供 Android,零额外依赖、零权限(网络流复用已有 INTERNET 权限)。
 */
internal object LoudnessAnalyzer {

    /** 分析结果。 */
    data class Result(val lufs: Double, val sampleRate: Int, val analyzedMs: Int)

    /**
     * 分析指定音频源的响度。
     *
     * @param url 网络或本地 URL(http(s):// 或文件路径)。
     * @param maxDurationMs 最多分析的时长(从头开始),默认 30 分钟(安全上限,
     *        正常歌曲会在解码到 EOS 前结束,得到标准 integrated loudness)。
     * @return [Result];分析失败抛出异常。
     */
    fun analyze(url: String, maxDurationMs: Int = 1800000): Result {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(url)
        } catch (e: Exception) {
            runCatching { extractor.release() }
            throw e
        }

        var audioTrackIndex = -1
        var sampleRate = 44100
        var channels = 2
        var mime: String? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val trackMime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (trackMime.startsWith("audio/")) {
                audioTrackIndex = i
                sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                mime = trackMime
                break
            }
        }
        if (audioTrackIndex < 0 || mime == null) {
            runCatching { extractor.release() }
            throw IllegalStateException("no audio track in $url")
        }
        extractor.selectTrack(audioTrackIndex)

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(extractor.getTrackFormat(audioTrackIndex), null, null, 0)
        codec.start()

        try {
            val meter = GatedLoudnessMeter(sampleRate, channels, maxDurationMs)
            val info = MediaCodec.BufferInfo()
            var sawInputEos = false

            while (true) {
                if (!sawInputEos) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)!!
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inputIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEos = true
                        } else {
                            codec.queueInputBuffer(
                                inputIndex, 0, sampleSize,
                                extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outputIndex >= 0) {
                    val outputBuffer = codec.getOutputBuffer(outputIndex)
                    var stop = false
                    if (outputBuffer != null && info.size > 0) {
                        if (!meter.feed(outputBuffer, info.size)) {
                            stop = true
                        }
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                    if (stop || info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                }
            }

            val lufs = meter.integratedLufs()
            if (lufs.isNaN() || lufs.isInfinite()) {
                throw IllegalStateException("no samples decoded from $url")
            }
            val analyzedMs = (meter.sampleCount * 1000 / sampleRate).toInt()
            return Result(lufs, sampleRate, analyzedMs)
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }
    }
}

/**
 * EBU R128 gated integrated loudness 分块计量器。
 *
 * 流式逐帧喂入 PCM,内部维护每通道 K-weighting 滤波器(状态跨块连续)、
 * 400ms 环形缓冲(存 K-weighted 平方值)、100ms hop 产出块,
 * 最终两轮门限求得 integrated loudness。
 */
internal class GatedLoudnessMeter(
    sampleRate: Int,
    channels: Int,
    maxDurationMs: Int,
) {
    private val channels: Int
    private val filters: List<KWeightingFilter>
    private val blockLen: Int          // 400ms 样本数
    private val hopLen: Int            // 100ms 样本数
    private val ringSq: Array<DoubleArray>  // [channel][blockLen] 环形:K-weighted 平方值
    private val runningSum: DoubleArray     // [channel] 当前窗口内平方和
    private var writePos: Int = 0
    var sampleCount: Long = 0       // 已处理样本数(每通道计数)
        private set
    private val blockZs: ArrayList<Double> = ArrayList()
    private val maxSamplesPerChannel: Long
    private var totalSq: Double = 0.0
    private var totalSamples: Long = 0L

    init {
        require(channels >= 1)
        this.channels = minOf(channels, 2)
        this.filters = (0 until this.channels).map { KWeightingFilter(sampleRate) }
        this.blockLen = (sampleRate * 400 / 1000).coerceAtLeast(1)
        this.hopLen = (sampleRate * 100 / 1000).coerceAtLeast(1)
        this.ringSq = Array(this.channels) { DoubleArray(blockLen) }
        this.runningSum = DoubleArray(this.channels)
        this.maxSamplesPerChannel = sampleRate.toLong() * (maxDurationMs / 1000L)
    }

    /** 喂入一块 PCM(16-bit 交错)。返回 false 表示已达分析时长上限,应停止喂入。 */
    fun feed(buffer: java.nio.ByteBuffer, size: Int): Boolean {
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        val ch = channels
        val frameSize = 2 * ch
        val frameCount = size / frameSize
        for (frame in 0 until frameCount) {
            if (sampleCount >= maxSamplesPerChannel) return false
            val base = frame * frameSize
            var combinedSq = 0.0
            for (c in 0 until ch) {
                val raw = buffer.getShort(base + c * 2).toInt()
                val x = raw / 32768.0
                val y = filters[c].process(x)
                val sq = y * y
                val old = ringSq[c][writePos]
                runningSum[c] += sq - old
                ringSq[c][writePos] = sq
                combinedSq += sq
            }
            totalSq += combinedSq
            totalSamples++
            writePos = (writePos + 1) % blockLen
            sampleCount++
            if (sampleCount >= blockLen &&
                (sampleCount - blockLen) % hopLen == 0L
            ) {
                var z = 0.0
                for (c in 0 until ch) z += runningSum[c]
                z /= blockLen
                blockZs.add(z)
            }
        }
        return true
    }

    /** 计算 gated integrated loudness(LUFS)。无有效数据返回 NaN。 */
    fun integratedLufs(): Double {
        if (blockZs.isEmpty() || totalSamples == 0L) return Double.NaN

        // 第一轮:absolute gate(-70 LUFS)
        val absGate = 10.0.pow((-70.0 + 0.691) / 10.0)
        var absSum = 0.0
        var absCount = 0
        for (z in blockZs) {
            if (z > absGate) { absSum += z; absCount++ }
        }
        if (absCount == 0) {
            // 极安静,无块过绝对门限,兜底用全段均方
            val z = totalSq / totalSamples
            return -0.691 + 10.0 * log10(z.coerceAtLeast(1e-12))
        }
        // 第二轮:relative gate(abs-gated 均值 -10 LU)
        val zMeanAbs = absSum / absCount
        val relGate = zMeanAbs * 0.1
        var relSum = 0.0
        var relCount = 0
        for (z in blockZs) {
            if (z > absGate && z > relGate) { relSum += z; relCount++ }
        }
        val finalZ = if (relCount == 0) zMeanAbs else relSum / relCount
        return -0.691 + 10.0 * log10(finalZ.coerceAtLeast(1e-12))
    }
}

/**
 * EBU R128 K-weighting:两级 biquad 串联(预加重 shelf + 高通 RLB)。
 * 系数用 EBU TECH 3321 标准固定系数表(48k/44.1k 精确,其它采样率取最接近者)。
 */
internal class KWeightingFilter(sampleRate: Int) {
    private val stage1: Biquad
    private val stage2: Biquad

    init {
        val (s1, s2) = coefficientsFor(sampleRate)
        stage1 = Biquad(s1[0], s1[1], s1[2], s1[3], s1[4])
        stage2 = Biquad(s2[0], s2[1], s2[2], s2[3], s2[4])
    }

    fun process(x: Double): Double = stage2.process(stage1.process(x))

    private fun coefficientsFor(sr: Int): Pair<DoubleArray, DoubleArray> {
        return when (sr) {
            48000 -> Pair(STAGE1_48K, STAGE2_48K)
            44100 -> Pair(STAGE1_44K, STAGE2_44K)
            else -> if (sr < 46000) Pair(STAGE1_44K, STAGE2_44K)
            else Pair(STAGE1_48K, STAGE2_48K)
        }
    }

    private companion object {
        // EBU TECH 3321 K-weighting 系数(顺序: b0, b1, b2, a1, a2)
        // a1/a2 为传递函数分母系数,差分方程为减法(见 Biquad.process)。
        private val STAGE1_48K = doubleArrayOf(
            1.53512485958697, -2.69169618940638, 1.19839281085285,
            -1.69065929318241, 0.73248077421585
        )
        private val STAGE2_48K = doubleArrayOf(
            1.0, -2.0, 1.0,
            -1.99004745483398, 0.99007225036653
        )
        private val STAGE1_44K = doubleArrayOf(
            1.53090959966746, -2.65091438192596, 1.16905317746076,
            -1.66363706312434, 0.71264612449092
        )
        private val STAGE2_44K = doubleArrayOf(
            1.0, -2.0, 1.0,
            -1.98917551073170, 0.98922153047043
        )
    }
}

/** 直接 II 型转置 biquad。y = b0*x + z1; z1 = b1*x - a1*y + z2; z2 = b2*x - a2*y。 */
private class Biquad(
    private val b0: Double,
    private val b1: Double,
    private val b2: Double,
    private val a1: Double,
    private val a2: Double,
) {
    private var z1 = 0.0
    private var z2 = 0.0

    fun process(x: Double): Double {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
