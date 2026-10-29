package com.ra7al.muxer;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.File;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Copies the video and/or audio tracks of downloaded files into one MP4, without re-encoding. */
public class Ra7alMuxerPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "ra7al_muxer");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"remux".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final List<String> inputs = call.argument("inputs");
        final String output = call.argument("output");
        final Boolean v = call.argument("video");
        final Boolean a = call.argument("audio");
        new Thread(() -> {
            try {
                remux(inputs, output, v == null || v, a == null || a);
                main.post(() -> result.success(null));
            } catch (Exception e) {
                new File(output).delete();
                main.post(() -> result.error("remux", String.valueOf(e.getMessage()), null));
            }
        }).start();
    }

    private static void remux(List<String> inputs, String output, boolean wantVideo, boolean wantAudio) throws Exception {
        List<MediaExtractor> opened = new ArrayList<>();
        MediaMuxer muxer = null;
        try {
            MediaExtractor videoEx = null, audioEx = null;
            int videoIn = -1, audioIn = -1;
            for (String path : inputs) {
                MediaExtractor ex = new MediaExtractor();
                ex.setDataSource(path);
                opened.add(ex);
                for (int i = 0; i < ex.getTrackCount(); i++) {
                    String mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME);
                    if (mime == null) continue;
                    if (wantVideo && videoEx == null && mime.startsWith("video/")) {
                        videoEx = ex;
                        videoIn = i;
                    } else if (wantAudio && audioEx == null && mime.startsWith("audio/")) {
                        audioEx = ex;
                        audioIn = i;
                    }
                }
            }
            if (wantVideo && videoEx == null) throw new IllegalStateException("No video track");
            if (wantAudio && !wantVideo && audioEx == null) throw new IllegalStateException("No audio track");

            muxer = new MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            int videoOut = -1, audioOut = -1;
            if (videoEx != null) {
                MediaFormat f = videoEx.getTrackFormat(videoIn);
                videoOut = muxer.addTrack(f);
                if (f.containsKey(MediaFormat.KEY_ROTATION)) muxer.setOrientationHint(f.getInteger(MediaFormat.KEY_ROTATION));
            }
            if (audioEx != null) audioOut = muxer.addTrack(audioEx.getTrackFormat(audioIn));
            muxer.start();
            if (videoEx != null) copy(videoEx, videoIn, muxer, videoOut);
            if (audioEx != null) copy(audioEx, audioIn, muxer, audioOut);
            muxer.stop();
        } finally {
            if (muxer != null) {
                try {
                    muxer.release();
                } catch (Exception ignored) {
                }
            }
            for (MediaExtractor ex : opened) ex.release();
        }
    }

    private static void copy(MediaExtractor ex, int track, MediaMuxer muxer, int outTrack) {
        for (int i = 0; i < ex.getTrackCount(); i++) ex.unselectTrack(i);
        ex.selectTrack(track);
        MediaFormat f = ex.getTrackFormat(track);
        int size = f.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE) ? Math.max(f.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), 1 << 20) : 4 << 20;
        ByteBuffer buf = ByteBuffer.allocate(size);
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        while (true) {
            buf.clear();
            int n = ex.readSampleData(buf, 0);
            if (n < 0) break;
            info.offset = 0;
            info.size = n;
            info.presentationTimeUs = ex.getSampleTime();
            info.flags = (ex.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
            muxer.writeSampleData(outTrack, buf, info);
            ex.advance();
        }
    }
}
