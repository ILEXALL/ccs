package com.example.ccs_app

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val photoPickerChannelName = "ccs/photo_picker"
    private val deviceIdentityChannelName = "ccs/device_identity"
    private val screenAwakeChannelName = "ccs/screen_awake"
    private val notificationsChannelName = "ccs/system_notifications"
    private val liveLocationChannelName = "ccs/live_location_background"
    private val notificationChannelId = "ccs_updates"
    private val pickPhotoRequestCode = 7001
    private var pendingPhotoResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, photoPickerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPhoto" -> openPhotoPicker(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceIdentityChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceId" -> result.success(getStableAndroidDeviceId())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenAwakeChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        val title = call.argument<String>("title") ?: "CCS"
                        val body = call.argument<String>("body") ?: ""
                        val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                        showNotification(id, title, body)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, liveLocationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, LiveLocationService::class.java).apply {
                            putExtra("uid", call.argument<String>("uid"))
                            putExtra("shareScope", call.argument<String>("shareScope"))
                            putExtra("promptAtMillis", call.argument<Long>("promptAtMillis") ?: 0L)
                            putExtra("expiresAtMillis", call.argument<Long>("expiresAtMillis") ?: 0L)
                            putExtra(
                                "uploadIntervalSeconds",
                                call.argument<Int>("uploadIntervalSeconds") ?: 15
                            )
                            putExtra(
                                "minimumUploadDistanceMeters",
                                call.argument<Double>("minimumUploadDistanceMeters") ?: 10.0
                            )

                            val visibleToUserIds = call.argument<List<String>>("visibleToUserIds")
                                ?: emptyList()
                            putStringArrayListExtra(
                                "visibleToUserIds",
                                ArrayList(visibleToUserIds)
                            )
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }

                        result.success(null)
                    }

                    "stop" -> {
                        stopService(Intent(this, LiveLocationService::class.java))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            notificationChannelId,
            "CCS updates",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Spot, comment, like and chat notifications"
        }

        manager.createNotificationChannel(channel)
    }

    private fun showNotification(id: Int, title: String, body: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, builder.build())
    }

    private fun openPhotoPicker(result: MethodChannel.Result) {
        if (pendingPhotoResult != null) {
            result.error("picker_busy", "Photo picker is already open.", null)
            return
        }

        pendingPhotoResult = result

        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }

        startActivityForResult(
            Intent.createChooser(intent, "Choose spot photo"),
            pickPhotoRequestCode
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != pickPhotoRequestCode) {
            return
        }

        val result = pendingPhotoResult
        pendingPhotoResult = null

        if (result == null) {
            return
        }

        val imageUri = data?.data

        if (resultCode != Activity.RESULT_OK || imageUri == null) {
            result.success(null)
            return
        }

        try {
            result.success(copyPickedImageToCache(imageUri))
        } catch (error: Exception) {
            result.error("photo_copy_failed", error.message, null)
        }
    }

    private fun copyPickedImageToCache(imageUri: Uri): String {
        val inputStream = contentResolver.openInputStream(imageUri)
            ?: throw IllegalStateException("Could not open selected image.")

        val photoFile = File(cacheDir, "ccs_spot_${System.currentTimeMillis()}.jpg")

        inputStream.use { input ->
            FileOutputStream(photoFile).use { output ->
                input.copyTo(output)
            }
        }

        return photoFile.absolutePath
    }

    private fun getStableAndroidDeviceId(): String? {
        val androidId = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ANDROID_ID
        )?.trim()

        if (androidId.isNullOrEmpty() || androidId == "9774d56d682e549c") {
            return null
        }

        return "android:$androidId"
    }
}
