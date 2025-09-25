package com.tapes.cast

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object CastManager {
    private val _hasDevices = MutableStateFlow(false)
    val hasDevices: StateFlow<Boolean> = _hasDevices
    init {
        GlobalScope.launch(Dispatchers.Default) {
            while (true) {
                _hasDevices.value = false // TODO: wire Google Cast discovery
                delay(10_000)
            }
        }
    }
}
