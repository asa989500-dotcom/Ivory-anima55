package com.aaje.ivory.media;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Putting a finished video where the phone's own gallery will find it.
 *
 * <h2>Why an export is not finished when the file is written</h2>
 *
 * An app's private folder is not somewhere a person can reach. A video saved
 * there exists, plays inside IVORY, and is invisible to the gallery, to the
 * share sheet, and to every other app on the phone — which for somebody who
 * has just spent an evening on it is indistinguishable from the export having
 * failed.
 *
 * MediaStore is how a file becomes a video the phone knows about. On Android
 * 10 and later it is also the only way, since an app cannot simply write into
 * Movies any more, and it is the reason IVORY does not ask for
 * MANAGE_EXTERNAL_STORAGE — the permission Play reviews by hand and refuses
 * to apps that do not need it.
 */
public class IvoryStore extends GodotPlugin {

	private static final String TAG = "IvoryStore";

	public IvoryStore(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "IvoryStore";
	}

	/**
	 * Copies a finished file into the gallery under Movies/IVORY.
	 *
	 * Returns the public path or URI it now lives at, or an empty string if
	 * it could not be published — which the caller reports rather than
	 * swallowing, because a video the user cannot find is worth saying out
	 * loud.
	 */
	@UsedByGodot
	public String publish_video(String path, String name) {
		File source = new File(path);
		if (!source.exists()) {
			return "";
		}
		String title = (name == null || name.isEmpty())
			? source.getName() : name;
		try {
			ContentResolver resolver = getActivity() == null ? null
				: getActivity().getContentResolver();
			if (resolver == null) {
				return "";
			}
			ContentValues values = new ContentValues();
			values.put(MediaStore.Video.Media.DISPLAY_NAME, title);
			values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				values.put(MediaStore.Video.Media.RELATIVE_PATH,
					Environment.DIRECTORY_MOVIES + "/IVORY");
				// Hidden from the gallery until the copy is complete, so a
				// half-written video never appears as a broken thumbnail.
				values.put(MediaStore.Video.Media.IS_PENDING, 1);
			}
			Uri item = resolver.insert(
				MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
			if (item == null) {
				return "";
			}
			try (InputStream in = new FileInputStream(source);
					OutputStream out = resolver.openOutputStream(item)) {
				if (out == null) {
					return "";
				}
				byte[] buffer = new byte[1 << 16];
				int read;
				while ((read = in.read(buffer)) > 0) {
					out.write(buffer, 0, read);
				}
			}
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				ContentValues done = new ContentValues();
				done.put(MediaStore.Video.Media.IS_PENDING, 0);
				resolver.update(item, done, null, null);
			}
			return item.toString();
		} catch (Exception e) {
			Log.e(TAG, "publish failed", e);
			return "";
		}
	}
}
