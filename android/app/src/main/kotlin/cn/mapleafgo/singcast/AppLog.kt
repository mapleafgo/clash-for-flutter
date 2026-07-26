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
    /// 独立文件名：不能与 Dart 侧 LogFileWriter 的 singcast.log 同名。
    /// 两侧各持独立句柄和缓冲写同一路径时，原生日志会被丢掉——曾导致
    /// VPN 建立/断开/热重载的原生记录全部缺失，故障完全无法排查。
    const val LOG_FILE = "singcast-native.log"

    @Volatile private var writer: BufferedWriter? = null
    private val dateFormat = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    fun init(logDir: File): File {
        val logFile = File(logDir, LOG_FILE)

        // Truncate if too large
        if (logFile.exists() && logFile.length() > MAX_LOG_SIZE) {
            logFile.writeText("")
        }

        // 引擎重建会再次 init：先关旧 writer，否则每次重建泄漏一个文件句柄
        close()
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

    /// 关闭日志文件句柄。init 会先调用它，Activity 销毁时也应调用。
    @Synchronized
    fun close() {
        val w = writer ?: return
        writer = null
        try {
            w.flush()
            w.close()
        } catch (_: Exception) {
            // 关闭失败无可挽回，忽略
        }
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
