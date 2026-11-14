package com.example.imagedatefix

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class MainActivity : FlutterActivity() {
    private val channel = "foto_tarih_duzenleyici"
    private val request = 4901
    private var folder: Uri? = null
    private var pending: MethodChannel.Result? = null
    @Volatile private var cancelRequested = false
    private val format = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> {
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    ), request)
                }
                "openFile" -> {
                    val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
                    if (uri == null) result.error("BAD_URI", "Dosya yolu geçersiz.", null)
                    else try {
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, contentResolver.getType(uri) ?: "image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(true)
                    } catch (e: Exception) { result.error("OPEN_FAILED", e.message, null) }
                }
                "fixDates" -> {
                    cancelRequested = false
                    val root = folder
                    if (root == null) { result.error("NO_FOLDER", "Önce klasör seç.", null); return@setMethodCallHandler }
                    val assignUnknown = call.argument<Boolean>("assignUnknown") ?: false
                    val fallback = call.argument<String>("fallbackDate")?.let { runCatching { java.time.LocalDate.parse(it.substringBefore('T')).atStartOfDay() }.getOrNull() }
                    Thread {
                        val files = mutableListOf<DocumentFile>()
                        scan(DocumentFile.fromTreeUri(this, root), files)
                        var written = 0; var failed = 0; var noDate = 0; var assigned = 0
                        val okFiles = mutableListOf<String>(); val problemFiles = mutableListOf<String>()
                        files.forEach { file ->
                            if (cancelRequested) return@forEach
                            val parsed = parse(file.name ?: "")
                            val date = parsed ?: if (assignUnknown && fallback != null) { assigned++; fallback.plusMinutes(assigned.toLong() - 1) } else null
                            if (date == null) { noDate++; problemFiles += file.uri.toString() }
                            else if (write(file.uri, date)) { written++; okFiles += file.uri.toString() }
                            else { failed++; problemFiles += file.uri.toString() }
                            runOnUiThread { MethodChannel(engine.dartExecutor.binaryMessenger, channel).invokeMethod("progress", mapOf("value" to ((files.indexOf(file) + 1).toDouble() / files.size), "current" to (files.indexOf(file) + 1), "total" to files.size)) }
                        }
                        runOnUiThread { result.success(mapOf("total" to files.size, "written" to written, "noDate" to noDate, "assigned" to assigned, "failed" to failed, "okFiles" to okFiles, "problemFiles" to problemFiles)) }
                    }.start()
                }
                "cancel" -> { cancelRequested = true; result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(code, resultCode, data)
        if (code != request) return
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            contentResolver.takePersistableUriPermission(uri, ((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)))
            folder = uri
            pending?.success(DocumentFile.fromTreeUri(this, uri)?.name ?: "Klasör seçildi")
        } else pending?.success(null)
        pending = null
    }

    private fun scan(dir: DocumentFile?, out: MutableList<DocumentFile>) {
        dir?.listFiles()?.forEach { f -> if (f.isDirectory) scan(f, out) else if ((f.name ?: "").substringAfterLast('.', "").lowercase() in setOf("jpg", "jpeg", "png", "heic", "webp")) out += f }
    }

    private fun parse(name: String): LocalDateTime? {
        val full = Regex("(?<!\\d)(20\\d{2})[-_. ]?([01]\\d)[-_. ]?([0-3]\\d)(?:[ T_-]?([0-2]\\d)[:.-]?([0-5]\\d)[:.-]?([0-5]\\d))?").find(name)
        if (full != null) return try { LocalDateTime.of(full.groupValues[1].toInt(), full.groupValues[2].toInt(), full.groupValues[3].toInt(), full.groupValues[4].ifEmpty { "0" }.toInt(), full.groupValues[5].ifEmpty { "0" }.toInt(), full.groupValues[6].ifEmpty { "0" }.toInt()) } catch (_: Exception) { null }
        val millis = Regex("(?<!\\d)(1[5-9]\\d{11}|20\\d{11})(?!\\d)").find(name)
        return millis?.let { java.time.LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(it.value.toLong()), java.time.ZoneId.systemDefault()) }
    }

    private fun write(uri: Uri, date: LocalDateTime): Boolean = try {
        contentResolver.openFileDescriptor(uri, "rw")?.use { p ->
            val e = ExifInterface(p.fileDescriptor); val v = date.format(format)
            e.setAttribute(ExifInterface.TAG_DATETIME, v); e.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, v); e.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, v); e.saveAttributes()
        } ?: return false
        true
    } catch (_: Exception) { false }
}
