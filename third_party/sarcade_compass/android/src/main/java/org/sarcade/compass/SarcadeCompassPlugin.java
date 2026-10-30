package org.sarcade.compass;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

/** Heading of the rotation vector sensor (fused by Android) and its accuracy. */
public class SarcadeCompassPlugin implements FlutterPlugin, EventChannel.StreamHandler, SensorEventListener {
    private EventChannel channel;
    private SensorManager sensors;
    private EventChannel.EventSink sink;
    private int status = -1;
    private final float[] rotation = new float[9];
    private final float[] orientation = new float[3];
    private final float[] vector = new float[4];

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        sensors = (SensorManager) binding.getApplicationContext().getSystemService(Context.SENSOR_SERVICE);
        channel = new EventChannel(binding.getBinaryMessenger(), "org.sarcade/compass");
        channel.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stop();
        if (channel != null) channel.setStreamHandler(null);
        channel = null;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        stop();
        Sensor sensor = sensors == null ? null : sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
        if (sensor == null && sensors != null) sensor = sensors.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR);
        if (sensor == null) {
            events.error("no_sensor", "No compass on this device", null);
            return;
        }
        sink = events;
        status = -1;
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI);
    }

    @Override
    public void onCancel(Object arguments) {
        stop();
    }

    private void stop() {
        if (sensors != null) sensors.unregisterListener(this);
        sink = null;
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (sink == null) return;
        float[] v = event.values;
        if (v.length < 3) return;
        for (int i = 0; i < 4; i++) vector[i] = i < v.length ? v[i] : 0f;
        if (v.length < 4) {
            // Older devices: the scalar part is computed by Android.
            float[] three = new float[] {v[0], v[1], v[2]};
            SensorManager.getRotationMatrixFromVector(rotation, three);
        } else {
            // Some Samsung devices refuse a vector longer than 4.
            SensorManager.getRotationMatrixFromVector(rotation, vector);
        }
        SensorManager.getOrientation(rotation, orientation);
        double heading = Math.toDegrees(orientation[0]);
        if (Double.isNaN(heading) || Double.isInfinite(heading)) return;
        heading = (heading % 360 + 360) % 360;
        double accuracy = -1;
        if (v.length > 4 && v[4] > 0 && !Float.isNaN(v[4])) accuracy = Math.toDegrees(v[4]);
        sink.success(new double[] {heading, accuracy, status});
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        status = accuracy;
    }
}
