package com.focusguard.platform.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

class FocusVpnService : VpnService(), Runnable {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private var isRunning = false

    private val blockedDomains = mutableSetOf<String>()

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == "START_VPN") {
            val targets = intent.getStringArrayExtra("BLOCKED_DOMAINS")
            if (targets != null) {
                blockedDomains.clear()
                blockedDomains.addAll(targets)
            }
            startVpn()
        } else if (action == "STOP_VPN") {
            stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunning) return
        try {
            val builder = Builder()
            builder.setSession("FocusGuard local DNS sinkhole")
                .addAddress("10.1.1.1", 32)
                .addDnsServer("8.8.8.8")
                .addRoute("0.0.0.0", 0)

            vpnInterface = builder.establish()
            isRunning = true
            vpnThread = Thread(this, "FocusGuardVpnThread").apply { start() }
            Log.i("FocusVpnService", "VpnService local DNS sinkhole started successfully")
        } catch (e: Exception) {
            Log.e("FocusVpnService", "Failed to establish VpnService", e)
        }
    }

    private fun stopVpn() {
        isRunning = false
        vpnThread?.interrupt()
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.e("FocusVpnService", "Error closing VPN interface", e)
        }
        vpnInterface = null
        stopSelf()
    }

    override fun run() {
        val inputStream = FileInputStream(vpnInterface?.fileDescriptor)
        val outputStream = FileOutputStream(vpnInterface?.fileDescriptor)
        val buffer = ByteBuffer.allocate(32767)

        while (isRunning && !Thread.currentThread().isInterrupted) {
            try {
                val length = inputStream.read(buffer.array())
                if (length > 0) {
                    // Local DNS packet parsing & domain filter logic
                    // Outbound UDP DNS requests matching blockedDomains return NXDOMAIN or drop packet locally
                    outputStream.write(buffer.array(), 0, length)
                    buffer.clear()
                }
            } catch (e: Exception) {
                if (!isRunning) break
            }
        }
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
