package com.prplegryn.lisn;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.MediaMetadataRetriever;
import android.os.Build;
import android.os.Environment;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "lisn/music_library";
    private static final int PERMISSION_REQUEST_CODE = 7107;
    private static final Set<String> AUDIO_EXTENSIONS = new HashSet<>(Arrays.asList(
            ".aac",
            ".aiff",
            ".alac",
            ".amr",
            ".ape",
            ".flac",
            ".m4a",
            ".mid",
            ".midi",
            ".mp3",
            ".oga",
            ".ogg",
            ".opus",
            ".wav",
            ".wma"
    ));

    private MethodChannel.Result pendingPermissionResult;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL
        ).setMethodCallHandler(this::handleMusicLibraryCall);
    }

    private void handleMusicLibraryCall(MethodCall call, MethodChannel.Result result) {
        if ("requestAudioPermission".equals(call.method)) {
            requestAudioPermission(result);
            return;
        }
        if ("scanMusic".equals(call.method)) {
            scanMusic(result);
            return;
        }
        result.notImplemented();
    }

    private void requestAudioPermission(MethodChannel.Result result) {
        if (hasAudioPermission()) {
            result.success(true);
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true);
            return;
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "Audio permission request is already active.", null);
            return;
        }

        pendingPermissionResult = result;
        requestPermissions(new String[]{audioPermission()}, PERMISSION_REQUEST_CODE);
    }

    private void scanMusic(MethodChannel.Result result) {
        if (!hasAudioPermission()) {
            result.error("permission_denied", "Audio permission has not been granted.", null);
            return;
        }

        File musicDirectory = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_MUSIC
        );
        List<Map<String, Object>> tracks = new ArrayList<>();
        scanDirectory(musicDirectory, tracks);
        result.success(tracks);
    }

    private boolean hasAudioPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        return checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED;
    }

    private String audioPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return Manifest.permission.READ_MEDIA_AUDIO;
        }
        return Manifest.permission.READ_EXTERNAL_STORAGE;
    }

    private void scanDirectory(File directory, List<Map<String, Object>> tracks) {
        if (directory == null || !directory.exists() || !directory.isDirectory()) {
            return;
        }

        File[] children = directory.listFiles();
        if (children == null) {
            return;
        }
        Arrays.sort(children, (first, second) ->
                first.getName().compareToIgnoreCase(second.getName())
        );

        for (File child : children) {
            if (child.isDirectory()) {
                scanDirectory(child, tracks);
            } else if (isAudioFile(child)) {
                tracks.add(trackFromFile(child));
            }
        }
    }

    private boolean isAudioFile(File file) {
        String name = file.getName().toLowerCase(Locale.US);
        for (String extension : AUDIO_EXTENSIONS) {
            if (name.endsWith(extension)) {
                return true;
            }
        }
        return false;
    }

    private Map<String, Object> trackFromFile(File file) {
        Map<String, Object> track = new HashMap<>();
        track.put("id", file.getAbsolutePath());
        track.put("path", file.getAbsolutePath());
        track.put("title", titleFromName(file.getName()));
        track.put("artist", "未知艺术家");

        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            retriever.setDataSource(file.getAbsolutePath());
            putStringMetadata(
                    track,
                    "title",
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            );
            putStringMetadata(
                    track,
                    "artist",
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            );
            putStringMetadata(
                    track,
                    "album",
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            );
            String duration = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION
            );
            if (duration != null && !duration.trim().isEmpty()) {
                track.put("durationMs", Long.parseLong(duration));
            }
        } catch (Exception ignored) {
            // Some local files have unsupported metadata. The file itself is still usable.
        } finally {
            try {
                retriever.release();
            } catch (Exception ignored) {
            }
        }

        return track;
    }

    private void putStringMetadata(Map<String, Object> track, String key, String value) {
        if (value != null && !value.trim().isEmpty()) {
            track.put(key, value.trim());
        }
    }

    private String titleFromName(String fileName) {
        int dotIndex = fileName.lastIndexOf('.');
        if (dotIndex > 0) {
            return fileName.substring(0, dotIndex);
        }
        return fileName;
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            String[] permissions,
            int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != PERMISSION_REQUEST_CODE || pendingPermissionResult == null) {
            return;
        }

        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        pendingPermissionResult.success(granted);
        pendingPermissionResult = null;
    }
}
