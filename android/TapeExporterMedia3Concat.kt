package com.tapes.export

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.transformer.EditedMediaItem
import com.google.android.exoplayer2.transformer.EditedMediaItemSequence
import com.google.android.exoplayer2.transformer.ProgressHolder
import com.google.android.exoplayer2.transformer.Transformer
import com.tapes.model.Tape
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

object TapeExporterMedia3Concat {
    suspend fun export(context: Context, tape: Tape, onDone: (Uri?) -> Unit) = withContext(Dispatchers.IO) {
        try {
            val items = tape.clips.map { EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(it.assetLocalId))).build() }
            val seq = EditedMediaItemSequence(items)
            val outFile = File(context.cacheDir, "tape_${System.currentTimeMillis()}.mp4")
            val transformer = Transformer.Builder(context).setRemoveAudio(false).build()
            transformer.start(seq, outFile.absolutePath)

            val progress = ProgressHolder()
            while (true) {
                val state = transformer.getProgress(progress)
                if (state == Transformer.PROGRESS_STATE_NOT_STARTED) Thread.sleep(100)
                else if (state == Transformer.PROGRESS_STATE_IN_PROGRESS) Thread.sleep(200)
                else break
            }

            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, "Tape_${System.currentTimeMillis()}.mp4")
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Tapes")
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                resolver.openOutputStream(uri).use { out -> outFile.inputStream().use { it.copyTo(out!!) } }
                outFile.delete(); onDone(uri)
            } else onDone(null)
        } catch (e: Exception) { e.printStackTrace(); onDone(null) }
    }
}
