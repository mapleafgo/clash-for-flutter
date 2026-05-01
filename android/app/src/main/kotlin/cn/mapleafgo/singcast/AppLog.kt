package cn.mapleafgo.singcast

import android.util.Log
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object AppLog {
    private const val TAG = "SingcastVpn"
    private const val MAX_LOG_SIZE = 5L * 1024 * 1024 // 5MB
    private const val LOG_FILE = "singcast.log"

    private var writer: BufferedWriter? = null
    private val dateFormat = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    fun init(logDir: File): File {
        val logFile = File(logDir, LOG_FILE)

        // Rotate if too large
        if (logFile.exists() && logFile.length() > MAX_LOG_SIZE) {
            logFile.delete()
        }

        writer = BufferedWriter(FileWriter(logFile, true))
        i(TAG, "========== AppLog initialized ==========")
        return logFile
    }

    fun d(tag: String, msg: String) {
        Log.d(tag, msg)
        write("D", tag, msg)
    }

    fun i(tag: String, msg: String) {
        Log.i(tag, msg)
        write("I", tag, msg)
    }

    fun w(tag: String, msg: String, tr: Throwable? = null) {
        if (tr != null) Log.w(tag, msg, tr) else Log.w(tag, msg)
        write("W", tag, msg, tr)
    }

    fun e(tag: String, msg: String, tr: Throwable? = null) {
        if (tr != null) Log.e(tag, msg, tr) else Log.e(tag, msg)
        write("E", tag, msg, tr)
    }

    @Synchronized
    private fun write(level: String, tag: String, msg: String, tr: Throwable? = null) {
        val w = writer ?: return
        try {
            val ts = dateFormat.format(Date())
            w.write("$ts $level/$tag: $msg\n")
            tr?.let {
                val sw = StringWriter()
                it.printStackTrace(PrintWriter(sw))
                w.write(sw.toString())
            }
            w.flush()
        } catch (_: Exception) {
            // Silently ignore write failures
        }
    }
}
