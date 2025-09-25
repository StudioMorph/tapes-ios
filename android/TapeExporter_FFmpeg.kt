package com.tapes.export

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import com.tapes.model.Orientation
import com.tapes.model.Tape
import com.tapes.model.TransitionStyle
import com.tapes.player.TransitionPicker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

object TapeExporterFFmpeg {
    suspend fun export(context: Context, tape: Tape, onDone: (Uri?) -> Unit) = withContext(Dispatchers.IO) {
        val inputs = try {
            tape.clips.mapIndexed { idx, clip ->
                val uri = Uri.parse(clip.assetLocalId)
                val temp = File(context.cacheDir, "tapes_in_${idx}.mp4")
                copyUriToFile(context.contentResolver, uri, temp); temp
            }
        } catch (e: Exception) { e.printStackTrace(); onDone(null); return@withContext }
        if (inputs.isEmpty()) { onDone(null); return@withContext }

        val boundaries = (tape.clips.size - 1).coerceAtLeast(0)
        val seq: List<TransitionStyle> = if (tape.transition == TransitionStyle.Randomise)
            TransitionPicker.sequenceForTape(tape.id, boundaries) else List(boundaries) { tape.transition }
        val duration = if (tape.transition == TransitionStyle.Randomise)
            TransitionPicker.clampedDuration(tape.transitionDuration) else tape.transitionDuration

        val cmd = buildCommand(inputs, seq, duration, tape.orientation)

        val session = FFmpegKit.execute(cmd)
        if (ReturnCode.isSuccess(session.returnCode)) {
            val outFile = File(context.cacheDir, "tapes_out.mp4")
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, "Tape_${System.currentTimeMillis()}.mp4")
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Tapes")
            }
            val resolver = context.contentResolver
            val target = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            if (target != null) {
                resolver.openOutputStream(target).use { out -> outFile.inputStream().use { it.copyTo(out!!) } }
                inputs.forEach { it.delete() }
                outFile.delete()
                onDone(target)
            } else onDone(null)
        } else onDone(null)
    }

    private fun copyUriToFile(resolver: ContentResolver, uri: Uri, file: File) {
        resolver.openInputStream(uri).use { input ->
            FileOutputStream(file).use { out -> if (input != null) input.copyTo(out) }
        }
    }

    private fun buildCommand(inputs: List<File>, seq: List<TransitionStyle>, duration: Double, orientation: Orientation): String {
        val inputArgs = inputs.joinToString(" ") { "-i ${it.absolutePath}" }
        val d = String.format("%.3f", duration)
        val (W, H) = if (orientation == Orientation.Portrait) 1080 to 1920 else 1920 to 1080

        val sb = StringBuilder()
        for (i in inputs.indices) {
            sb.append("[$i:v]scale=w=$W:h=-2:flags=bicubic,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p[v$i];")
            sb.append("[$i:a]anull[a$i];")
        }

        var vPrev = "v0"; var aPrev = "a0"
        for (i in 1 until inputs.size) {
            val vCur = "v$i"; val aCur = "a$i"
            val vOut = "v${i}o"; val aOut = "a${i}o"
            val tr = when (seq.getOrNull(i-1) ?: TransitionStyle.None) {
                TransitionStyle.Crossfade -> "fade"
                TransitionStyle.SlideLR -> "slideleft"
                TransitionStyle.SlideRL -> "slideright"
                else -> null
            }
            if (tr == null) {
                sb.append("[$vPrev][$aPrev][$vCur][$aCur]concat=n=2:v=1:a=1[$vOut][$aOut];")
            } else {
                sb.append("[$vPrev][$vCur]xfade=transition=$tr:duration=$d:offset=0[$vOut];")
                sb.append("[$aPrev][$aCur]acrossfade=d=$d:c1=tri:c2=tri[$aOut];")
            }
            vPrev = vOut; aPrev = aOut
        }

        val outPath = File(inputs.first().parentFile, "tapes_out.mp4").absolutePath
        val map = "-map [$vPrev] -map [$aPrev] -c:v libx264 -crf 18 -preset veryfast -c:a aac -b:a 192k -movflags +faststart -y"
        return "$inputArgs -filter_complex "${sb}" $map "$outPath""
    }
}
