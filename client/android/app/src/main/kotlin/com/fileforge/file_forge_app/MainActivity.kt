package com.fileforge.file_forge_app

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "com.fileforge.file_forge_app/downloads"
    private val requestCodeWriteStorage = 1001

    // API 28 이하 런타임 권한 요청 중 보류 중인 호출 상태
    private var pendingResult: MethodChannel.Result? = null
    private var pendingFilename: String? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val filename = call.argument<String>("filename") ?: ""
                    val bytes = call.argument<ByteArray>("bytes") ?: byteArrayOf()
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                        ContextCompat.checkSelfPermission(
                            this, Manifest.permission.WRITE_EXTERNAL_STORAGE
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        // 권한 미허용 상태: 결과를 보류하고 런타임 요청
                        pendingResult = result
                        pendingFilename = filename
                        pendingBytes = bytes
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            requestCodeWriteStorage
                        )
                    } else {
                        try {
                            saveToDownloads(filename, bytes)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != requestCodeWriteStorage) return

        val result = pendingResult ?: return
        val filename = pendingFilename ?: ""
        val bytes = pendingBytes ?: byteArrayOf()
        pendingResult = null
        pendingFilename = null
        pendingBytes = null

        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            try {
                saveToDownloads(filename, bytes)
                result.success(null)
            } catch (e: Exception) {
                result.error("SAVE_FAILED", e.message, null)
            }
        } else {
            result.error("PERMISSION_DENIED", "WRITE_EXTERNAL_STORAGE 권한이 거부되었습니다", null)
        }
    }

    private fun saveToDownloads(filename: String, bytes: ByteArray) {
        val mimeType = getMimeType(filename)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+ (Android 10+): MediaStore.Downloads 사용
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore insert failed")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("Failed to open output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            // API 28 이하: public Downloads 폴더 직접 저장
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            downloadsDir.mkdirs()
            FileOutputStream(File(downloadsDir, filename)).use { it.write(bytes) }
        }
    }

    private fun getMimeType(filename: String): String {
        val ext = filename.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }
}
