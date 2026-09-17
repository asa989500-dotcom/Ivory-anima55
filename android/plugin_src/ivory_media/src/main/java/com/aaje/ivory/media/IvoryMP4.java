package com.aaje.ivory.media;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.media.Image;
import android.util.Log;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.godotengine.godot.Dictionary;

import java.io.File;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * H.264 and AAC straight out of the phone, with no FFmpeg anywhere.
 *
 * <h2>Why this exists instead of the native library</h2>
 *
 * The FFmpeg route needed the NDK, five git submodules and a cross-compile
 * per ABI, and it ended with several megabytes of encoder riding inside every
 * APK — to do a job the phone already has silicon for. Every Android device
 * since 2014 has a hardware H.264 encoder sitting behind MediaCodec, and it
 * is faster than libx264 will ever be on a battery, because it is not
 * software.
 *
 * So: Godot to JNI to MediaCodec to MediaMuxer to an MP4. Nothing is bundled,
 * nothing is cross-compiled, and the export runs on hardware.
 *
 * <h2>The one awkward part</h2>
 *
 * MediaMuxer will not accept a track after it has started, and a codec does
 * not report its output format until it has actually encoded something. So
 * with both video and audio there is a moment where one track is producing
 * packets and the other has not yet declared itself.
 *
 * Those packets are held here — see {@link #pending} — and written the
 * instant the muxer starts. It is a handful of frames at most, and the
 * alternative is either dropping the start of the sound or refusing audio
 * altogether, both of which are worse than a short queue.
 */
public class IvoryMP4 extends GodotPlugin {

	private static final String TAG = "IvoryMP4";
	private static final String VIDEO = MediaFormat.MIMETYPE_VIDEO_AVC;
	private static final String AUDIO = MediaFormat.MIMETYPE_AUDIO_AAC;
	/** How long to wait on a codec buffer before giving the caller a turn. */
	private static final long WAIT_US = 10000;

	private MediaCodec videoCodec;
	private MediaCodec audioCodec;
	private MediaMuxer muxer;
	private int videoTrack = -1;
	private int audioTrack = -1;
	private boolean muxing = false;
	private boolean wantAudio = false;
	private boolean opened = false;

	private int width, height, fps, audioRate, audioChannels;
	private long videoIndex = 0;
	private long audioIndex = 0;
	private String error = "";
	private String encoderName = "";
	private String outputPath = "";

	/** Packets encoded before the muxer could be started. See the note above. */
	private static class Held {
		boolean video;
		byte[] bytes;
		MediaCodec.BufferInfo info;
	}

	private final List<Held> pending = new ArrayList<>();

	public IvoryMP4(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "IvoryMP4";
	}

	// ------------------------------------------------------------- opening

	@UsedByGodot
	public boolean open(String path, int w, int h, int rate, int bitrate,
			boolean audio, int aRate, int aChannels, int aKbps) {
		close();
		error = "";
		try {
			if (w < 2 || h < 2 || (w & 1) != 0 || (h & 1) != 0) {
				error = "Unsupported resolution";
				return false;
			}
			if (rate < 1 || rate > 120) {
				error = "Unsupported FPS";
				return false;
			}
			width = w;
			height = h;
			fps = rate;
			outputPath = path;
			File out = new File(path);
			File parent = out.getParentFile();
			if (parent != null && !parent.exists() && !parent.mkdirs()) {
				error = "Could not create the folder for the video";
				return false;
			}

			MediaFormat vf = MediaFormat.createVideoFormat(VIDEO, w, h);
			vf.setInteger(MediaFormat.KEY_COLOR_FORMAT,
				MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
			// A bitrate is compulsory here — MediaCodec has no CRF. When the
			// caller has none, one is worked out from the picture, which is
			// what every other tool that talks to MediaCodec does.
			int bits = bitrate > 0 ? bitrate : guessBitrate(w, h, rate);
			vf.setInteger(MediaFormat.KEY_BIT_RATE, bits);
			vf.setInteger(MediaFormat.KEY_FRAME_RATE, rate);
			// A keyframe every two seconds: small enough to scrub, large
			// enough not to waste a third of the file on them.
			vf.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2);
			if (android.os.Build.VERSION.SDK_INT >= 21) {
				vf.setInteger(MediaFormat.KEY_BITRATE_MODE,
					MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR);
			}
			videoCodec = MediaCodec.createEncoderByType(VIDEO);
			videoCodec.configure(vf, null, null,
				MediaCodec.CONFIGURE_FLAG_ENCODE);
			try {
				encoderName = videoCodec.getName();
			} catch (Exception ignored) {
				encoderName = "mediacodec";
			}
			videoCodec.start();

			wantAudio = audio;
			if (wantAudio) {
				audioRate = aRate > 0 ? aRate : 48000;
				audioChannels = Math.max(1, Math.min(2, aChannels));
				MediaFormat af = MediaFormat.createAudioFormat(AUDIO,
					audioRate, audioChannels);
				af.setInteger(MediaFormat.KEY_AAC_PROFILE,
					MediaCodecInfo.CodecProfileLevel.AACObjectLC);
				af.setInteger(MediaFormat.KEY_BIT_RATE,
					Math.max(64, Math.min(512, aKbps)) * 1000);
				af.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 32768);
				audioCodec = MediaCodec.createEncoderByType(AUDIO);
				audioCodec.configure(af, null, null,
					MediaCodec.CONFIGURE_FLAG_ENCODE);
				audioCodec.start();
			}

			muxer = new MediaMuxer(path,
				MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
			opened = true;
			return true;
		} catch (Exception e) {
			error = "Could not start the encoder: " + e.getMessage();
			Log.e(TAG, "open failed", e);
			close();
			return false;
		}
	}

	private static int guessBitrate(int w, int h, int fps) {
		// Roughly 0.07 bits per pixel per frame, which is generous for the
		// flat colour and clean line an animation is made of, and is clamped
		// so a tiny canvas is not starved and a 4K one is not absurd.
		long bits = (long) w * h * fps / 14;
		return (int) Math.max(1200000L, Math.min(bits, 60000000L));
	}

	// -------------------------------------------------------------- frames

	@UsedByGodot
	public boolean add_frame(byte[] rgba) {
		if (!opened || videoCodec == null) {
			error = "The encoder is not open";
			return false;
		}
		if (rgba == null || rgba.length < width * height * 4) {
			error = "Invalid frame buffer";
			return false;
		}
		try {
			int index = videoCodec.dequeueInputBuffer(WAIT_US * 20);
			if (index < 0) {
				// The encoder is behind. Draining it is what lets it catch
				// up; returning an error here would fail an export for being
				// briefly busy.
				drainVideo(false);
				index = videoCodec.dequeueInputBuffer(WAIT_US * 40);
				if (index < 0) {
					error = "The hardware encoder stopped accepting frames";
					return false;
				}
			}
			// getInputImage hands back the planes in whatever layout this
			// particular chip wants — I420 on some, NV12 on others — with the
			// strides filled in. Writing to it is the only way to feed a
			// flexible colour format without guessing per device.
			Image img = videoCodec.getInputImage(index);
			int size;
			if (img != null) {
				size = fillImage(img, rgba);
			} else {
				ByteBuffer buf = videoCodec.getInputBuffer(index);
				if (buf == null) {
					error = "No encoder buffer";
					return false;
				}
				size = fillI420(buf, rgba);
			}
			long pts = videoIndex * 1000000L / fps;
			videoCodec.queueInputBuffer(index, 0, size, pts, 0);
			videoIndex++;
			drainVideo(false);
			return true;
		} catch (Exception e) {
			error = "H.264 encoding failed: " + e.getMessage();
			Log.e(TAG, "add_frame failed", e);
			return false;
		}
	}

	/**
	 * RGBA into the codec's own planes, converted to YUV as it goes.
	 *
	 * The chroma is sampled from one pixel of each two-by-two block rather
	 * than averaged over four. On photographic video that would be visible;
	 * on drawn animation, where a two-by-two block is nearly always one flat
	 * colour, it is not — and it is four times less arithmetic per frame in
	 * a loop that runs for every pixel of every frame of the whole export.
	 */
	private int fillImage(Image img, byte[] rgba) {
		Image.Plane[] planes = img.getPlanes();
		ByteBuffer yb = planes[0].getBuffer();
		ByteBuffer ub = planes[1].getBuffer();
		ByteBuffer vb = planes[2].getBuffer();
		int yStride = planes[0].getRowStride();
		int uStride = planes[1].getRowStride();
		int uPixel = planes[1].getPixelStride();
		int vStride = planes[2].getRowStride();
		int vPixel = planes[2].getPixelStride();

		byte[] row = new byte[yStride];
		for (int y = 0; y < height; y++) {
			int src = y * width * 4;
			for (int x = 0; x < width; x++) {
				int r = rgba[src] & 0xFF;
				int g = rgba[src + 1] & 0xFF;
				int b = rgba[src + 2] & 0xFF;
				src += 4;
				row[x] = (byte) clamp8((66 * r + 129 * g + 25 * b + 128 >> 8) + 16);
			}
			yb.position(y * yStride);
			yb.put(row, 0, Math.min(yStride, row.length));
		}

		int halfW = width / 2;
		int halfH = height / 2;
		byte[] urow = new byte[uStride];
		byte[] vrow = new byte[vStride];
		for (int y = 0; y < halfH; y++) {
			for (int x = 0; x < halfW; x++) {
				int src = ((y * 2) * width + (x * 2)) * 4;
				int r = rgba[src] & 0xFF;
				int g = rgba[src + 1] & 0xFF;
				int b = rgba[src + 2] & 0xFF;
				byte u = (byte) clamp8((-38 * r - 74 * g + 112 * b + 128 >> 8) + 128);
				byte v = (byte) clamp8((112 * r - 94 * g - 18 * b + 128 >> 8) + 128);
				urow[x * uPixel] = u;
				vrow[x * vPixel] = v;
			}
			ub.position(y * uStride);
			ub.put(urow, 0, Math.min(uStride, halfW * uPixel));
			vb.position(y * vStride);
			vb.put(vrow, 0, Math.min(vStride, halfW * vPixel));
		}
		return width * height * 3 / 2;
	}

	/** The fallback for a device that will not hand back an Image: plain I420. */
	private int fillI420(ByteBuffer buf, byte[] rgba) {
		buf.clear();
		byte[] out = new byte[width * height * 3 / 2];
		int at = 0;
		for (int y = 0; y < height; y++) {
			int src = y * width * 4;
			for (int x = 0; x < width; x++) {
				int r = rgba[src] & 0xFF;
				int g = rgba[src + 1] & 0xFF;
				int b = rgba[src + 2] & 0xFF;
				src += 4;
				out[at++] = (byte) clamp8((66 * r + 129 * g + 25 * b + 128 >> 8) + 16);
			}
		}
		int uAt = width * height;
		int vAt = uAt + (width * height / 4);
		for (int y = 0; y < height / 2; y++) {
			for (int x = 0; x < width / 2; x++) {
				int src = ((y * 2) * width + (x * 2)) * 4;
				int r = rgba[src] & 0xFF;
				int g = rgba[src + 1] & 0xFF;
				int b = rgba[src + 2] & 0xFF;
				out[uAt++] = (byte) clamp8((-38 * r - 74 * g + 112 * b + 128 >> 8) + 128);
				out[vAt++] = (byte) clamp8((112 * r - 94 * g - 18 * b + 128 >> 8) + 128);
			}
		}
		buf.put(out);
		return out.length;
	}

	private static int clamp8(int v) {
		return v < 0 ? 0 : (v > 255 ? 255 : v);
	}

	// --------------------------------------------------------------- sound

	@UsedByGodot
	public boolean add_audio(byte[] pcm, int samples) {
		if (!wantAudio || audioCodec == null) {
			return !wantAudio;
		}
		if (pcm == null || samples <= 0) {
			return true;
		}
		try {
			int wanted = samples * audioChannels * 2;
			int at = 0;
			while (at < wanted) {
				int index = audioCodec.dequeueInputBuffer(WAIT_US * 20);
				if (index < 0) {
					drainAudio(false);
					index = audioCodec.dequeueInputBuffer(WAIT_US * 40);
					if (index < 0) {
						error = "The AAC encoder stopped accepting sound";
						return false;
					}
				}
				ByteBuffer buf = audioCodec.getInputBuffer(index);
				if (buf == null) {
					error = "No audio buffer";
					return false;
				}
				buf.clear();
				int take = Math.min(buf.remaining(),
					Math.min(wanted - at, pcm.length - at));
				if (take <= 0) {
					audioCodec.queueInputBuffer(index, 0, 0, 0, 0);
					break;
				}
				buf.put(pcm, at, take);
				long pts = audioIndex * 1000000L / audioRate;
				audioCodec.queueInputBuffer(index, 0, take, pts, 0);
				audioIndex += take / (audioChannels * 2);
				at += take;
				drainAudio(false);
			}
			return true;
		} catch (Exception e) {
			error = "AAC encoding failed: " + e.getMessage();
			Log.e(TAG, "add_audio failed", e);
			return false;
		}
	}

	// ------------------------------------------------------------ draining

	private void drainVideo(boolean end) {
		if (videoCodec == null) {
			return;
		}
		MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
		while (true) {
			int out = videoCodec.dequeueOutputBuffer(info, end ? WAIT_US * 50 : 0);
			if (out == MediaCodec.INFO_TRY_AGAIN_LATER) {
				return;
			}
			if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
				videoTrack = muxer.addTrack(videoCodec.getOutputFormat());
				startIfReady();
				continue;
			}
			if (out < 0) {
				continue;
			}
			ByteBuffer buf = videoCodec.getOutputBuffer(out);
			// The codec config packet is the SPS and PPS. The muxer took them
			// from the output format already, so writing them again would put
			// a duplicate parameter set into the stream.
			if (buf != null && info.size > 0
					&& (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
				write(true, buf, info);
			}
			videoCodec.releaseOutputBuffer(out, false);
			if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
				return;
			}
		}
	}

	private void drainAudio(boolean end) {
		if (audioCodec == null) {
			return;
		}
		MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
		while (true) {
			int out = audioCodec.dequeueOutputBuffer(info, end ? WAIT_US * 50 : 0);
			if (out == MediaCodec.INFO_TRY_AGAIN_LATER) {
				return;
			}
			if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
				audioTrack = muxer.addTrack(audioCodec.getOutputFormat());
				startIfReady();
				continue;
			}
			if (out < 0) {
				continue;
			}
			ByteBuffer buf = audioCodec.getOutputBuffer(out);
			if (buf != null && info.size > 0
					&& (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
				write(false, buf, info);
			}
			audioCodec.releaseOutputBuffer(out, false);
			if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
				return;
			}
		}
	}

	private void startIfReady() {
		if (muxing || muxer == null) {
			return;
		}
		if (videoTrack < 0) {
			return;
		}
		if (wantAudio && audioTrack < 0) {
			return;
		}
		muxer.start();
		muxing = true;
		for (Held one : pending) {
			ByteBuffer bb = ByteBuffer.wrap(one.bytes);
			bb.position(0);
			bb.limit(one.bytes.length);
			one.info.offset = 0;
			muxer.writeSampleData(one.video ? videoTrack : audioTrack, bb,
				one.info);
		}
		pending.clear();
	}

	private void write(boolean video, ByteBuffer buf,
			MediaCodec.BufferInfo info) {
		if (muxing) {
			buf.position(info.offset);
			buf.limit(info.offset + info.size);
			muxer.writeSampleData(video ? videoTrack : audioTrack, buf, info);
			return;
		}
		// Not started yet — hold on to a copy. The buffer itself goes back to
		// the codec the moment this returns, so keeping the reference would
		// be keeping a promise the codec has not made.
		Held held = new Held();
		held.video = video;
		held.bytes = new byte[info.size];
		buf.position(info.offset);
		buf.get(held.bytes, 0, info.size);
		MediaCodec.BufferInfo copy = new MediaCodec.BufferInfo();
		copy.set(0, info.size, info.presentationTimeUs, info.flags);
		held.info = copy;
		pending.add(held);
	}

	// -------------------------------------------------------------- ending

	@UsedByGodot
	public int finish() {
		if (!opened) {
			return -1;
		}
		// With buffer input — which is what this uses — the end of the stream
		// is an empty buffer carrying the end-of-stream flag.
		// signalEndOfInputStream() is for surface input only and throws here.
		try {
			if (videoCodec != null) {
				int index = videoCodec.dequeueInputBuffer(WAIT_US * 50);
				if (index >= 0) {
					videoCodec.queueInputBuffer(index, 0, 0,
						videoIndex * 1000000L / fps,
						MediaCodec.BUFFER_FLAG_END_OF_STREAM);
				}
				drainVideo(true);
			}
			if (audioCodec != null) {
				int index = audioCodec.dequeueInputBuffer(WAIT_US * 50);
				if (index >= 0) {
					audioCodec.queueInputBuffer(index, 0, 0,
						audioIndex * 1000000L / audioRate,
						MediaCodec.BUFFER_FLAG_END_OF_STREAM);
				}
				drainAudio(true);
			}
			if (!muxing) {
				error = "Nothing was encoded";
				close();
				return -2;
			}
			close();
			return 0;
		} catch (Exception e) {
			error = "Could not finish the video: " + e.getMessage();
			Log.e(TAG, "finish failed", e);
			close();
			return -3;
		}
	}

	@UsedByGodot
	public void cancel_export() {
		close();
		if (!outputPath.isEmpty()) {
			File f = new File(outputPath);
			if (f.exists()) {
				// A cancelled export must not leave a file that looks like a
				// finished one. Half an MP4 opens, plays, and is wrong.
				boolean ignored = f.delete();
			}
		}
	}

	private void close() {
		try {
			if (videoCodec != null) {
				videoCodec.stop();
				videoCodec.release();
			}
		} catch (Exception ignored) {
		}
		try {
			if (audioCodec != null) {
				audioCodec.stop();
				audioCodec.release();
			}
		} catch (Exception ignored) {
		}
		try {
			if (muxer != null) {
				if (muxing) {
					muxer.stop();
				}
				muxer.release();
			}
		} catch (Exception ignored) {
		}
		videoCodec = null;
		audioCodec = null;
		muxer = null;
		videoTrack = -1;
		audioTrack = -1;
		muxing = false;
		opened = false;
		videoIndex = 0;
		audioIndex = 0;
		pending.clear();
	}

	// ------------------------------------------------------------- telling

	@UsedByGodot
	public String last_error() {
		return error;
	}

	@UsedByGodot
	public String encoder_name() {
		return encoderName;
	}

	@UsedByGodot
	public boolean is_hardware() {
		String n = encoderName.toLowerCase();
		// Google's software encoders announce themselves; anything else on a
		// phone is the chip.
		return !n.startsWith("omx.google") && !n.startsWith("c2.android");
	}

	@UsedByGodot
	public Dictionary capabilities() {
		Dictionary d = new Dictionary();
		d.put("hardware_h264", true);
		d.put("aac", true);
		d.put("tuned", true);
		d.put("max_audio_kbps", 512);
		d.put("backend", "mediacodec");
		return d;
	}
}
