package com.tapes.cast

import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cast
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import android.widget.Toast

@Composable
fun CastButton() {
    val context = LocalContext.current
    val hasDevices by CastManager.hasDevices.collectAsState()
    if (!hasDevices) return
    IconButton(onClick = { Toast.makeText(context, "Casting not yet implemented", Toast.LENGTH_SHORT).show() }) {
        Icon(Icons.Filled.Cast, contentDescription = "Cast")
    }
}
