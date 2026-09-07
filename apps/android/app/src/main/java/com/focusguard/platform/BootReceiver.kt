package com.focusguard.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.focusguard.platform.vpn.FocusVpnService

/**
 * FocusGuard Android Boot Receiver
 * Automatically restores background enforcement and local DNS sinkhole
 * after phone reboot or system package update without requiring manual user interaction.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i(TAG, "Received system broadcast action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED) {

            Log.i(TAG, "Restoring FocusGuard local protection after device reboot...")

            try {
                // Launch local VPN sinkhole service if previously configured
                val vpnIntent = Intent(context, FocusVpnService::class.java).apply {
                    this.action = "START_VPN_PROTECTION"
                }
                context.startForegroundService(vpnIntent)
                Log.i(TAG, "FocusVpnService foreground service initiated successfully.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to auto-restart FocusVpnService on boot", e)
            }
        }
    }

    companion object {
        private const val TAG = "FocusGuardBootReceiver"
    }
}
