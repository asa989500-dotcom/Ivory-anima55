package com.aaje.ivory.media;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.OpenableColumns;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.collection.ArraySet;

import org.godotengine.godot.Godot;
import org.godotengine.godot.Dictionary;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Set;

/**
 * Ivory's Android Storage Access Framework bridge.
 *
 * Keeps the Android-specific Uri handling in one place. Godot receives a real
 * app-private file path, while Android retains ownership of the original Uri.
 * No storage permission is required for files explicitly selected by the user.
 */
public final class IvoryFilePicker extends GodotPlugin {
    private static final String TAG = "IvoryFilePicker";
    private static final int OPEN_FILE = 1101;
    private Activity activity;

    public IvoryFilePicker(Godot godot) {
        super(godot);
        activity = godot.getActivity();
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "IvoryFilePicker";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new ArraySet<>();
        signals.add(new SignalInfo("file_picked", String.class, String.class));
        signals.add(new SignalInfo("file_pick_cancelled"));
        signals.add(new SignalInfo("file_pick_failed", String.class));
        return signals;
    }

    @UsedByGodot
    public void openFilePicker(String mimeType) {
        openFilePicker(mimeType, false);
    }

    @UsedByGodot
    public void openFilePicker(String mimeType, boolean allowMultiple) {
        if (activity == null) {
            emitSignal("file_pick_failed", "activity_unavailable");
            return;
        }
        String type = mimeType == null || mimeType.isEmpty() ? "*/*" : mimeType;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(type);
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple);
        try {
            activity.startActivityForResult(Intent.createChooser(intent, "Choose a file"), OPEN_FILE);
        } catch (Exception e) {
            Log.e(TAG, "Could not open Android file picker", e);
            emitSignal("file_pick_failed", "picker_unavailable");
        }
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent resultData) {
        if (requestCode != OPEN_FILE) {
            return;
        }
        if (resultCode != Activity.RESULT_OK || resultData == null) {
            emitSignal("file_pick_cancelled");
            return;
        }

        try {
            Uri uri = resultData.getData();
            if (uri == null && resultData.getClipData() != null && resultData.getClipData().getItemCount() > 0) {
                uri = resultData.getClipData().getItemAt(0).getUri();
            }
            if (uri == null) {
                emitSignal("file_pick_failed", "empty_uri");
                return;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                int flags = resultData.getFlags() &
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                try {
                    activity.getContentResolver().takePersistableUriPermission(uri, flags);
                } catch (Exception ignored) {
                    // Some providers do not expose persistable grants; the copy below is sufficient.
                }
            }
            File copied = copyToPrivateStorage(activity, uri);
            if (copied == null || !copied.isFile()) {
                emitSignal("file_pick_failed", "copy_failed");
                return;
            }
            String mime = activity.getContentResolver().getType(uri);
            emitSignal("file_picked", copied.getAbsolutePath(), mime == null ? "application/octet-stream" : mime);
        } catch (Exception e) {
            Log.e(TAG, "File pick failed", e);
            emitSignal("file_pick_failed", "pick_failed");
        }
    }

    @UsedByGodot
    public Dictionary getFileInfo(String absolutePath) {
        Dictionary result = new Dictionary();
        File file = absolutePath == null ? null : new File(absolutePath);
        result.put("ok", file != null && file.isFile());
        if (file != null && file.isFile()) {
            result.put("name", file.getName());
            result.put("path", file.getAbsolutePath());
            result.put("size", file.length());
            result.put("modified", file.lastModified());
        }
        return result;
    }

    public static File copyToPrivateStorage(Context context, Uri uri) throws Exception {
        File directory = new File(context.getFilesDir(), "_temp");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IllegalStateException("temp_directory_unavailable");
        }

        String name = queryName(context, uri);
        if (name == null || name.isEmpty()) {
            name = "import_" + System.currentTimeMillis();
        }
        name = sanitizeFileName(name);
        File destination = uniqueFile(directory, name);

        ContentResolver resolver = context.getContentResolver();
        try (InputStream in = resolver.openInputStream(uri)) {
            if (in == null) {
                throw new IllegalStateException("input_unavailable");
            }
            try (OutputStream out = new FileOutputStream(destination)) {
                byte[] buffer = new byte[1 << 16];
                int length;
                while ((length = in.read(buffer)) != -1) {
                    if (length > 0) {
                        out.write(buffer, 0, length);
                    }
                }
                out.flush();
            }
        }
        return destination;
    }

    private static File uniqueFile(File directory, String name) {
        File candidate = new File(directory, name);
        if (!candidate.exists()) {
            return candidate;
        }
        int dot = name.lastIndexOf('.');
        String stem = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; i < 10000; i++) {
            candidate = new File(directory, stem + "_" + i + ext);
            if (!candidate.exists()) {
                return candidate;
            }
        }
        return new File(directory, stem + "_" + System.currentTimeMillis() + ext);
    }

    private static String sanitizeFileName(String value) {
        String clean = value.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        if (clean.isEmpty() || clean.equals(".") || clean.equals("..")) {
            return "import_file";
        }
        return clean;
    }

    private static String queryName(Context context, Uri uri) {
        Cursor cursor = null;
        try {
            cursor = context.getContentResolver().query(uri, null, null, null, null);
            if (cursor != null) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0 && cursor.moveToFirst()) {
                    return cursor.getString(index);
                }
            }
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
        String fallback = uri.getLastPathSegment();
        return fallback == null ? "import_file" : fallback;
    }
}
