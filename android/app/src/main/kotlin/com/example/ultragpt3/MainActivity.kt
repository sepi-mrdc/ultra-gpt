package com.example.ultragpt3

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.ultragpt3/downloads"
        private const val FOLDER_NAME = "Ultra GPT"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidSdkInt" -> {
                    result.success(Build.VERSION.SDK_INT)
                }

                "saveDownload" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType =
                        call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Missing sourcePath or fileName", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val savedPath = saveToUltraGptFolder(sourcePath, fileName, mimeType)
                        result.success(savedPath)
                    } catch (error: Exception) {
                        result.error("SAVE_FAILED", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveToUltraGptFolder(
        sourcePath: String,
        fileName: String,
        mimeType: String,
    ): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalArgumentException("Source file not found.")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val uniqueName = uniqueDisplayName(fileName)
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, uniqueName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER_NAME",
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create download entry.")

            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Failed to open download output stream.")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            return "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER_NAME/$uniqueName"
        }

        @Suppress("DEPRECATION")
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val folder = File(downloadsDir, FOLDER_NAME)
        if (!folder.exists()) {
            folder.mkdirs()
        }

        val destination = uniqueFile(folder, fileName)
        sourceFile.copyTo(destination, overwrite = true)
        return destination.absolutePath
    }

    private fun uniqueDisplayName(fileName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return fileName
        }

        val resolver = applicationContext.contentResolver
        var candidate = fileName
        var suffix = 1

        while (displayNameExists(resolver, candidate)) {
            candidate = appendSuffix(fileName, suffix)
            suffix++
        }

        return candidate
    }

    private fun displayNameExists(
        resolver: android.content.ContentResolver,
        displayName: String,
    ): Boolean {
        val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
        val selectionArgs = arrayOf(
            displayName,
            "%${Environment.DIRECTORY_DOWNLOADS}/$FOLDER_NAME/%",
        )

        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            selection,
            selectionArgs,
            null,
        ).use { cursor ->
            return cursor != null && cursor.moveToFirst()
        }
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) {
            return candidate
        }

        var suffix = 1
        while (candidate.exists()) {
            candidate = File(directory, appendSuffix(fileName, suffix))
            suffix++
        }

        return candidate
    }

    private fun appendSuffix(fileName: String, suffix: Int): String {
        val dotIndex = fileName.lastIndexOf('.')
        return if (dotIndex > 0) {
            "${fileName.substring(0, dotIndex)} ($suffix)${fileName.substring(dotIndex)}"
        } else {
            "$fileName ($suffix)"
        }
    }
}
