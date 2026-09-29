package com.zhiteng.zhiteng_app

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.res.Configuration
import android.text.format.DateFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "zhiteng/system_datetime",
        ).setMethodCallHandler { call, result ->
            if (call.method != "pick") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            val initial = calendarFrom(args["initial"])
            val minimum = (args["minimum"] as? Number)?.toLong()
            val maximum = (args["maximum"] as? Number)?.toLong()
            var replied = false
            fun reply(value: Long?) {
                if (replied) return
                replied = true
                result.success(value)
            }
            val dateDialog =
                DatePickerDialog(
                    this,
                    { _, year, month, day ->
                        TimePickerDialog(
                            this,
                            { _, hour, minute ->
                                val picked = Calendar.getInstance()
                                picked.set(year, month, day, hour, minute, 0)
                                picked.set(Calendar.MILLISECOND, 0)
                                reply(picked.timeInMillis)
                            },
                            initial.get(Calendar.HOUR_OF_DAY),
                            initial.get(Calendar.MINUTE),
                            DateFormat.is24HourFormat(this),
                        ).apply {
                            setOnCancelListener { reply(null) }
                        }.show()
                    },
                    initial.get(Calendar.YEAR),
                    initial.get(Calendar.MONTH),
                    initial.get(Calendar.DAY_OF_MONTH),
                )
            minimum?.let { dateDialog.datePicker.minDate = it }
            maximum?.let { dateDialog.datePicker.maxDate = it }
            dateDialog.setOnCancelListener { reply(null) }
            dateDialog.show()
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "zhiteng/system_dialog",
        ).setMethodCallHandler { call, result ->
            if (call.method != "confirm") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            val title = args["title"] as? String ?: ""
            val message = args["message"] as? String ?: ""
            val stay = args["stay"] as? String ?: "取消"
            val discard = args["discard"] as? String ?: "确定"
            var replied = false
            fun reply(value: Boolean?) {
                if (replied) return
                replied = true
                result.success(value)
            }
            if (isFinishing) {
                reply(null)
                return@setMethodCallHandler
            }
            val night =
                resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                    Configuration.UI_MODE_NIGHT_YES
            val theme =
                if (night) {
                    android.R.style.Theme_DeviceDefault_Dialog_Alert
                } else {
                    android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
                }
            AlertDialog.Builder(this, theme)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton(stay) { _, _ -> reply(false) }
                .setPositiveButton(discard) { _, _ -> reply(true) }
                .setOnCancelListener { reply(null) }
                .show()
        }
    }

    private fun calendarFrom(value: Any?): Calendar {
        val calendar = Calendar.getInstance()
        val millis = (value as? Number)?.toLong()
        if (millis != null) calendar.timeInMillis = millis
        return calendar
    }
}
