package com.aaje.ivory.media;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.DisplayMetrics;
import android.view.Window;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.Dictionary;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/** Small, permission-free Android SDK facade shared by Ivory features. */
public final class IvoryAndroid extends GodotPlugin {
    public IvoryAndroid(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "IvoryAndroid";
    }

    @UsedByGodot
    public Dictionary sdkInfo() {
        Dictionary info = new Dictionary();
        info.put("sdk_int", Build.VERSION.SDK_INT);
        info.put("release", Build.VERSION.RELEASE == null ? "" : Build.VERSION.RELEASE);
        info.put("manufacturer", Build.MANUFACTURER == null ? "" : Build.MANUFACTURER);
        info.put("model", Build.MODEL == null ? "" : Build.MODEL);
        return info;
    }

    @UsedByGodot
    public boolean openUrl(String url) {
        try {
            if (url == null || url.isEmpty() || getActivity() == null) return false;
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            getActivity().startActivity(intent);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public boolean shareText(String text, String title) {
        try {
            if (getActivity() == null) return false;
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_TEXT, text == null ? "" : text);
            getActivity().startActivity(Intent.createChooser(send, title == null ? "Share" : title));
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public boolean vibrate(long milliseconds) {
        try {
            Context context = getActivity();
            if (context == null) return false;
            Vibrator vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
            if (vibrator == null || !vibrator.hasVibrator()) return false;
            long duration = Math.max(1L, Math.min(milliseconds, 2000L));
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE));
            } else {
                vibrator.vibrate(duration);
            }
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public Dictionary displayInfo() {
        Dictionary info = new Dictionary();
        if (getActivity() == null) return info;
        DisplayMetrics dm = getActivity().getResources().getDisplayMetrics();
        info.put("width_px", dm.widthPixels);
        info.put("height_px", dm.heightPixels);
        info.put("density", dm.density);
        info.put("density_dpi", dm.densityDpi);
        return info;
    }

    @UsedByGodot
    public boolean keepScreenOn(boolean enabled) {
        try {
            if (getActivity() == null) return false;
            Window window = getActivity().getWindow();
            if (enabled) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }
}
