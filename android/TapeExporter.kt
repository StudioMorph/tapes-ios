package com.tapes.export

import android.content.Context
import android.net.Uri
import com.tapes.model.Tape
import com.tapes.model.TransitionStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object TapeExporter {
    suspend fun export(context: Context, tape: Tape, onDone: (Uri?) -> Unit) = withContext(Dispatchers.IO) {
        val needsTransitions = tape.transition != TransitionStyle.None || (tape.transition == TransitionStyle.Randomise && tape.clips.size > 1)
        if (needsTransitions) TapeExporterFFmpeg.export(context, tape, onDone)
        else TapeExporterMedia3Concat.export(context, tape, onDone)
    }
}
