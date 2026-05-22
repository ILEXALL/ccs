package com.example.ccs_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "ccs/photo_picker"
    private val pickPhotoRequestCode = 7001
    private var pendingPhotoResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPhoto" -> openPhotoPicker(result)
                    else -> result.notImplemented()
                }
            }
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
}
