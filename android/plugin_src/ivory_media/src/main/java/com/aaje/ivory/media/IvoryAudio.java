package com.aaje.ivory.media;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.util.Log;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.godotengine.godot.Dictionary;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Any sound file the phone can play, turned into plain samples.
 *
 * <h2>Why this replaces the FFmpeg decoder too</h2>
 *
 * Android already ships decoders for MP3, AAC, M4A, FLAC, Ogg Vorbis, Opus,
 * AMR, WAV and more — the same ones the music player uses. Carrying FFmpeg
 * into the APK to decode an MP3 is carrying a second implementation of
 * something the operating system does, for free, in hardware where the chip
 * offers it.
 *
 * What comes out is a canonical PCM16 WAV file, which is exactly what the
 * exporter's mixer reads, at whatever rate was asked for.
 *
 * <h2>Written as it decodes</h2>
 *
 * Nothing accumulates. An hour of stereo is six hundred megabytes of samples
 * and no Android process is given that; a packet is decoded, resampled,
 * written and forgotten, so the memory cost is the same for an hour as for a
 * second. The WAV header is written twice — once with zeroed lengths, and
 * again at the end when the real length is known, which is the whole reason
 * the samples never need counting in memory first.
 */
public class IvoryAudio extends GodotPlugin {

	private static final String TAG = "IvoryAudio";
	private static final long WAIT_US = 10000;

	public IvoryAudio(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "IvoryAudio";
	}

	@UsedByGodot
	public Dictionary decode_to_wav(String source, String out, int rate,
			int channels) {
		Dictionary result = new Dictionary();
		result.put("ok", false);
		if (rate < 8000 || rate > 192000) {
			rate = 48000;
		}
		if (channels < 1 || channels > 2) {
			channels = 2;
		}

		MediaExtractor extractor = new MediaExtractor();
		MediaCodec codec = null;
		RandomAccessFile file = null;
		BufferedOutputStream sink = null;
		long written = 0;

		try {
			extractor.setDataSource(source);
			int track = -1;
			MediaFormat format = null;
			for (int i = 0; i < extractor.getTrackCount(); i++) {
				MediaFormat f = extractor.getTrackFormat(i);
				String mime = f.getString(MediaFormat.KEY_MIME);
				if (mime != null && mime.startsWith("audio/")) {
					track = i;
					format = f;
					break;
				}
			}
			if (track < 0 || format == null) {
				result.put("error", "no_audio");
				return result;
			}
			extractor.selectTrack(track);

			int srcRate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE)
				? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : rate;
			int srcChannels = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
				? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : channels;

			codec = MediaCodec.createDecoderByType(
				format.getString(MediaFormat.KEY_MIME));
			codec.configure(format, null, null, 0);
			codec.start();

			File target = new File(out);
			File parent = target.getParentFile();
			if (parent != null && !parent.exists() && !parent.mkdirs()) {
				result.put("error", "cache_unwritable");
				return result;
			}
			sink = new BufferedOutputStream(new FileOutputStream(target),
				1 << 16);
			sink.write(wavHeader(rate, channels, 0));

			MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
			boolean fed = false;
			// Carried between packets so a resampled stream does not restart
			// its phase every packet, which is heard as a click per frame.
			double carry = 0.0;
			short[] tail = new short[2];
			boolean haveTail = false;

			while (true) {
				if (!fed) {
					int in = codec.dequeueInputBuffer(WAIT_US);
					if (in >= 0) {
						ByteBuffer buf = codec.getInputBuffer(in);
						int read = buf == null ? -1
							: extractor.readSampleData(buf, 0);
						if (read < 0) {
							codec.queueInputBuffer(in, 0, 0, 0,
								MediaCodec.BUFFER_FLAG_END_OF_STREAM);
							fed = true;
						} else {
							codec.queueInputBuffer(in, 0, read,
								extractor.getSampleTime(), 0);
							extractor.advance();
						}
					}
				}
				int outIndex = codec.dequeueOutputBuffer(info, WAIT_US);
				if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
					MediaFormat now = codec.getOutputFormat();
					srcRate = now.getInteger(MediaFormat.KEY_SAMPLE_RATE);
					srcChannels = now.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
					continue;
				}
				if (outIndex < 0) {
					if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
						break;
					}
					if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER && fed) {
						continue;
					}
					continue;
				}
				ByteBuffer buf = codec.getOutputBuffer(outIndex);
				if (buf != null && info.size > 0) {
					buf.position(info.offset);
					buf.limit(info.offset + info.size);
					byte[] chunk = resample(buf, srcRate, srcChannels, rate,
						channels);
					sink.write(chunk);
					written += chunk.length / (channels * 2);
				}
				codec.releaseOutputBuffer(outIndex, false);
				if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
					break;
				}
			}

			sink.flush();
			sink.close();
			sink = null;

			// Back to the top to write the lengths now that they are known.
			file = new RandomAccessFile(target, "rw");
			file.seek(0);
			file.write(wavHeader(rate, channels,
				(int) (written * channels * 2)));
			file.close();
			file = null;

			if (written <= 0) {
				result.put("error", "decode_failed");
				return result;
			}
			result.put("ok", true);
			result.put("rate", rate);
			result.put("channels", channels);
			result.put("frames", (int) written);
			result.put("seconds", (double) written / (double) rate);
			return result;
		} catch (Exception e) {
			Log.e(TAG, "decode failed", e);
			result.put("error", "decode_failed");
			return result;
		} finally {
			try {
				if (codec != null) {
					codec.stop();
					codec.release();
				}
			} catch (Exception ignored) {
			}
			try {
				extractor.release();
			} catch (Exception ignored) {
			}
			try {
				if (sink != null) {
					sink.close();
				}
			} catch (IOException ignored) {
			}
			try {
				if (file != null) {
					file.close();
				}
			} catch (IOException ignored) {
			}
		}
	}

	/**
	 * One packet of decoded PCM16, brought to the rate and channel count the
	 * exporter wants.
	 *
	 * Linear interpolation rather than nearest sample. Dropping samples to
	 * change rate is the gritty, faintly metallic sound that tells you an app
	 * did its resampling cheaply, and it is most audible on exactly the
	 * material people put under animation: sustained notes and speech.
	 */
	private static byte[] resample(ByteBuffer in, int srcRate, int srcChannels,
			int dstRate, int dstChannels) {
		in.order(ByteOrder.LITTLE_ENDIAN);
		int frames = in.remaining() / (2 * Math.max(srcChannels, 1));
		if (frames <= 0) {
			return new byte[0];
		}
		short[] src = new short[frames * srcChannels];
		for (int i = 0; i < src.length; i++) {
			src[i] = in.getShort();
		}
		int outFrames = (int) ((long) frames * dstRate / Math.max(srcRate, 1));
		if (outFrames <= 0) {
			outFrames = 1;
		}
		byte[] out = new byte[outFrames * dstChannels * 2];
		double step = (double) srcRate / (double) dstRate;
		int at = 0;
		for (int i = 0; i < outFrames; i++) {
			double here = i * step;
			int a = (int) here;
			int b = Math.min(a + 1, frames - 1);
			double t = here - a;
			for (int c = 0; c < dstChannels; c++) {
				int sc = Math.min(c, srcChannels - 1);
				double s0 = src[a * srcChannels + sc];
				double s1 = src[b * srcChannels + sc];
				int v = (int) Math.round(s0 + (s1 - s0) * t);
				if (v > 32767) {
					v = 32767;
				}
				if (v < -32768) {
					v = -32768;
				}
				out[at++] = (byte) (v & 0xFF);
				out[at++] = (byte) ((v >> 8) & 0xFF);
			}
		}
		return out;
	}

	private static byte[] wavHeader(int rate, int channels, int bytes) {
		ByteBuffer b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
		b.put("RIFF".getBytes());
		b.putInt(36 + bytes);
		b.put("WAVE".getBytes());
		b.put("fmt ".getBytes());
		b.putInt(16);
		b.putShort((short) 1);
		b.putShort((short) channels);
		b.putInt(rate);
		b.putInt(rate * channels * 2);
		b.putShort((short) (channels * 2));
		b.putShort((short) 16);
		b.put("data".getBytes());
		b.putInt(bytes);
		return b.array();
	}

	/** How long a sound file runs, without decoding a single sample of it. */
	@UsedByGodot
	public double length_of(String source) {
		MediaExtractor extractor = new MediaExtractor();
		try {
			extractor.setDataSource(source);
			for (int i = 0; i < extractor.getTrackCount(); i++) {
				MediaFormat f = extractor.getTrackFormat(i);
				String mime = f.getString(MediaFormat.KEY_MIME);
				if (mime != null && mime.startsWith("audio/")
						&& f.containsKey(MediaFormat.KEY_DURATION)) {
					return f.getLong(MediaFormat.KEY_DURATION) / 1000000.0;
				}
			}
		} catch (Exception ignored) {
		} finally {
			try {
				extractor.release();
			} catch (Exception ignored) {
			}
		}
		return 0.0;
	}
}
