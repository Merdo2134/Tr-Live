package com.trlive.tr_live

import android.Manifest
import android.annotation.TargetApi
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// TR Live ana ekranı (GitHub derlemesi bu dosyayı flutter create'in ürettiği MainActivity'nin yerine koyar).
//  * Uygulama açıkken ekran kendiliğinden kapanmaz (FLAG_KEEP_SCREEN_ON).
//  * Telefon araması: Android'in arama durumu (TelephonyManager) ve ses modu izlenir, Flutter'a "trlive/phone_call"
//    kanalından true/false gönderilir. Oda sesi kendi ses odağını aldığı için odak sinyali gelmeyen telefonlarda da çalışır.
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var telephony: TelephonyManager? = null
    private var callback: Any? = null
    private var legacyListener: PhoneStateListener? = null
    private var phoneBusy = false
    private var modeBusy = false
    private var lastSent: Boolean? = null
    private var polling = false

    private val modePoll = object : Runnable {
        override fun run() {
            if (!polling) return
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val m = am?.mode ?: AudioManager.MODE_NORMAL
                modeBusy = m == AudioManager.MODE_IN_CALL || m == AudioManager.MODE_RINGTONE || m == 4 // 4: MODE_CALL_SCREENING
            } catch (e: Exception) {
                modeBusy = false
            }
            emit()
            main.postDelayed(this, 700)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "trlive/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    val on = (call.arguments as? Boolean) ?: true
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "requestPhoneState" -> {
                    if (hasPhonePermission()) {
                        result.success(true)
                    } else {
                        try {
                            requestPermissions(arrayOf(Manifest.permission.READ_PHONE_STATE), 7341)
                        } catch (e: Exception) {
                        }
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "trlive/phone_call").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
                lastSent = null
                startWatch()
                emit()
            }

            override fun onCancel(arguments: Any?) {
                events = null
                stopWatch()
            }
        })
    }

    override fun onResume() {
        super.onResume()
        // İzin penceresinden dönünce (izin yeni verildiyse) arama izleme yeniden kurulur.
        if (events != null && callback == null && legacyListener == null) startWatch()
    }

    override fun onDestroy() {
        stopWatch()
        super.onDestroy()
    }

    private fun hasPhonePermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

    private fun emit() {
        val v = phoneBusy || modeBusy
        if (v == lastSent) return
        lastSent = v
        try {
            events?.success(v)
        } catch (e: Exception) {
        }
    }

    private fun startWatch() {
        if (!polling) {
            polling = true
            main.post(modePoll)
        }
        if (callback != null || legacyListener != null) return
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return
        telephony = tm
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                if (hasPhonePermission()) {
                    val cb = CallStateCallback { busy ->
                        main.post {
                            phoneBusy = busy
                            emit()
                        }
                    }
                    tm.registerTelephonyCallback(mainExecutor, cb)
                    callback = cb
                }
            } else {
                val l = LegacyCallListener { busy ->
                    phoneBusy = busy
                    emit()
                }
                @Suppress("DEPRECATION")
                tm.listen(l, PhoneStateListener.LISTEN_CALL_STATE)
                legacyListener = l
            }
        } catch (e: Exception) {
        }
    }

    private fun stopWatch() {
        polling = false
        main.removeCallbacks(modePoll)
        val tm = telephony
        try {
            if (tm != null && Build.VERSION.SDK_INT >= 31) {
                val cb = callback
                if (cb is TelephonyCallback) tm.unregisterTelephonyCallback(cb)
            }
            val l = legacyListener
            if (tm != null && l != null) {
                @Suppress("DEPRECATION")
                tm.listen(l, PhoneStateListener.LISTEN_NONE)
            }
        } catch (e: Exception) {
        }
        callback = null
        legacyListener = null
        phoneBusy = false
        modeBusy = false
    }
}

@TargetApi(31)
private class CallStateCallback(private val onBusy: (Boolean) -> Unit) : TelephonyCallback(), TelephonyCallback.CallStateListener {
    override fun onCallStateChanged(state: Int) {
        onBusy(state != TelephonyManager.CALL_STATE_IDLE)
    }
}

@Suppress("DEPRECATION")
private class LegacyCallListener(private val onBusy: (Boolean) -> Unit) : PhoneStateListener() {
    @Deprecated("Android 12 öncesi")
    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
        onBusy(state != TelephonyManager.CALL_STATE_IDLE)
    }
}
