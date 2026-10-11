package app.melodyflow.sonorynth

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface

class MainActivity : AudioServiceActivity(), SensorEventListener {
    private var manager: SensorManager? = null
    private var sink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        manager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "app.sonorynth.player/lyric_gyroscope").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
                val sensor = manager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
                if (sensor == null) {
                    events.endOfStream()
                } else {
                    manager?.registerListener(this@MainActivity, sensor, 33333)
                }
            }
            override fun onCancel(arguments: Any?) {
                manager?.unregisterListener(this@MainActivity)
                sink = null
            }
        })
    }

    override fun onSensorChanged(event: SensorEvent) {
        val x = event.values[0].toDouble()
        val y = event.values[1].toDouble()
        @Suppress("DEPRECATION")
        val rotation = windowManager.defaultDisplay.rotation
        val axes = when (rotation) {
            Surface.ROTATION_90 -> Pair(-y, x)
            Surface.ROTATION_180 -> Pair(-x, -y)
            Surface.ROTATION_270 -> Pair(y, -x)
            else -> Pair(x, y)
        }
        sink?.success(listOf(axes.first, axes.second, event.timestamp / 1e9))
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onPause() {
        manager?.unregisterListener(this)
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        if (sink != null) {
            manager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let {
                manager?.registerListener(this, it, 33333)
            }
        }
    }
    override fun onDestroy() {
        manager?.unregisterListener(this)
        sink = null
        super.onDestroy()
    }
}
