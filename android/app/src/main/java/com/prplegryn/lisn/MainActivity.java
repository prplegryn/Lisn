package com.prplegryn.lisn;

import android.Manifest;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.MediaMetadataRetriever;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Environment;
import android.net.Uri;
import android.provider.Settings;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
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
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String LIBRARY_CHANNEL = "lisn/music_library";
    private static final String PLAYER_CHANNEL = "lisn/player";
    private static final String PLAYER_EVENTS_CHANNEL = "lisn/player_events";
    private static final int PERMISSION_REQUEST_CODE = 7107;
    private static final String USER_STATE_PREFS = "lisn_user_state";
    private static final String FAVORITE_IDS_KEY = "favorite_ids";
    private static final String RECENT_IDS_KEY = "recent_ids";
    private static final String LIST_SEPARATOR = "\u001f";
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
    private EventChannel.EventSink playerEventSink;
    private MediaPlayer mediaPlayer;
    private String playerPath;
    private float playerVolume = 0.72f;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                LIBRARY_CHANNEL
        ).setMethodCallHandler(this::handleMusicLibraryCall);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                PLAYER_CHANNEL
        ).setMethodCallHandler(this::handlePlayerCall);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                PLAYER_EVENTS_CHANNEL
        ).setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                playerEventSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                playerEventSink = null;
            }
        });
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
        if ("readLyrics".equals(call.method)) {
            readLyrics(call, result);
            return;
        }
        if ("hasAllFilesAccess".equals(call.method)) {
            result.success(hasAllFilesAccess());
            return;
        }
        if ("openAllFilesSettings".equals(call.method)) {
            openAllFilesSettings(result);
            return;
        }
        if ("loadUserState".equals(call.method)) {
            loadUserState(result);
            return;
        }
        if ("saveUserState".equals(call.method)) {
            saveUserState(call, result);
            return;
        }
        result.notImplemented();
    }

    private void handlePlayerCall(MethodCall call, MethodChannel.Result result) {
        if ("play".equals(call.method)) {
            playAudio(call, result);
            return;
        }
        if ("pause".equals(call.method)) {
            pauseAudio(result);
            return;
        }
        if ("resume".equals(call.method)) {
            resumeAudio(result);
            return;
        }
        if ("stop".equals(call.method)) {
            stopAudio(result);
            return;
        }
        if ("seekTo".equals(call.method)) {
            seekAudio(call, result);
            return;
        }
        if ("setVolume".equals(call.method)) {
            setPlayerVolume(call, result);
            return;
        }
        if ("getState".equals(call.method)) {
            result.success(playerState());
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

    private void readLyrics(MethodCall call, MethodChannel.Result result) {
        String path = call.argument("path");
        if (path == null || path.trim().isEmpty()) {
            result.success(null);
            return;
        }

        File file = new File(path);
        if (!file.exists() || !file.isFile()) {
            result.success(null);
            return;
        }

        try {
            result.success(readTextFile(file));
        } catch (IOException exception) {
            result.error("lyrics_read_failed", "Unable to read lyrics file.", null);
        }
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

    private boolean hasAllFilesAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return true;
        }
        return Environment.isExternalStorageManager();
    }

    private void openAllFilesSettings(MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null);
            return;
        }

        Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
        intent.setData(Uri.parse("package:" + getPackageName()));
        try {
            startActivity(intent);
        } catch (Exception ignored) {
            startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
        }
        result.success(null);
    }

    private void loadUserState(MethodChannel.Result result) {
        SharedPreferences preferences = getSharedPreferences(USER_STATE_PREFS, MODE_PRIVATE);
        Map<String, Object> state = new HashMap<>();
        state.put("favoriteIds", splitList(preferences.getString(FAVORITE_IDS_KEY, "")));
        state.put("recentIds", splitList(preferences.getString(RECENT_IDS_KEY, "")));
        result.success(state);
    }

    private void saveUserState(MethodCall call, MethodChannel.Result result) {
        List<String> favoriteIds = stringListFromArgument(call.argument("favoriteIds"));
        List<String> recentIds = stringListFromArgument(call.argument("recentIds"));
        getSharedPreferences(USER_STATE_PREFS, MODE_PRIVATE)
                .edit()
                .putString(FAVORITE_IDS_KEY, joinList(favoriteIds))
                .putString(RECENT_IDS_KEY, joinList(recentIds))
                .apply();
        result.success(null);
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
        File lyricsFile = findLyricsFile(file);
        if (lyricsFile != null) {
            track.put("lyricsPath", lyricsFile.getAbsolutePath());
        }

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

    private File findLyricsFile(File audioFile) {
        File parent = audioFile.getParentFile();
        if (parent == null || !parent.exists() || !parent.isDirectory()) {
            return null;
        }

        File[] children = parent.listFiles();
        if (children == null) {
            return null;
        }

        String base = titleFromName(audioFile.getName()).toLowerCase(Locale.US);
        File best = null;
        for (File child : children) {
            if (!child.isFile()) {
                continue;
            }
            String name = child.getName().toLowerCase(Locale.US);
            if (!name.endsWith(".lrc")) {
                continue;
            }
            String lrcBase = name.substring(0, name.length() - 4);
            boolean exact = lrcBase.equals(base);
            boolean withSuffix = lrcBase.startsWith(base)
                    && isLyricsSuffix(lrcBase.substring(base.length()));
            if (!exact && !withSuffix) {
                continue;
            }
            if (best == null || child.getName().length() < best.getName().length()) {
                best = child;
            }
        }
        return best;
    }

    private boolean isLyricsSuffix(String suffix) {
        if (suffix.isEmpty()) {
            return true;
        }
        return suffix.startsWith(".")
                || suffix.startsWith("-")
                || suffix.startsWith("_")
                || suffix.startsWith(" ")
                || suffix.startsWith("(")
                || suffix.startsWith("[");
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

    private List<String> stringListFromArgument(Object value) {
        List<String> items = new ArrayList<>();
        if (!(value instanceof List)) {
            return items;
        }
        List<?> rawItems = (List<?>) value;
        for (Object item : rawItems) {
            if (item instanceof String && !((String) item).isEmpty()) {
                items.add((String) item);
            }
        }
        return items;
    }

    private String joinList(List<String> items) {
        StringBuilder builder = new StringBuilder();
        for (String item : items) {
            if (item == null || item.isEmpty()) {
                continue;
            }
            if (builder.length() > 0) {
                builder.append(LIST_SEPARATOR);
            }
            builder.append(item);
        }
        return builder.toString();
    }

    private List<String> splitList(String value) {
        List<String> items = new ArrayList<>();
        if (value == null || value.isEmpty()) {
            return items;
        }
        String[] parts = value.split(LIST_SEPARATOR);
        for (String part : parts) {
            if (!part.isEmpty()) {
                items.add(part);
            }
        }
        return items;
    }

    private void playAudio(MethodCall call, MethodChannel.Result result) {
        String path = call.argument("path");
        Number volume = call.argument("volume");
        if (volume != null) {
            playerVolume = Math.max(0f, Math.min(1f, volume.floatValue()));
        }
        if (path == null || path.trim().isEmpty()) {
            result.error("missing_path", "Audio path is required.", null);
            return;
        }
        File file = new File(path);
        if (!file.exists() || !file.isFile()) {
            result.error("missing_file", "Audio file does not exist.", null);
            return;
        }

        releasePlayer();
        mediaPlayer = new MediaPlayer();
        playerPath = file.getAbsolutePath();
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mediaPlayer.setAudioAttributes(
                        new AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build()
                );
            }
            mediaPlayer.setDataSource(playerPath);
            mediaPlayer.setOnCompletionListener(player -> {
                Map<String, Object> event = playerState();
                event.put("event", "completed");
                sendPlayerEvent(event);
            });
            mediaPlayer.prepare();
            mediaPlayer.setVolume(playerVolume, playerVolume);
            mediaPlayer.start();
            result.success(playerState());
        } catch (Exception exception) {
            releasePlayer();
            result.error("play_failed", "Unable to play audio file.", null);
        }
    }

    private void pauseAudio(MethodChannel.Result result) {
        try {
            if (mediaPlayer != null && mediaPlayer.isPlaying()) {
                mediaPlayer.pause();
            }
            result.success(playerState());
        } catch (Exception exception) {
            result.error("pause_failed", "Unable to pause audio.", null);
        }
    }

    private void resumeAudio(MethodChannel.Result result) {
        try {
            if (mediaPlayer != null && !mediaPlayer.isPlaying()) {
                mediaPlayer.start();
            }
            result.success(playerState());
        } catch (Exception exception) {
            result.error("resume_failed", "Unable to resume audio.", null);
        }
    }

    private void stopAudio(MethodChannel.Result result) {
        releasePlayer();
        result.success(playerState());
    }

    private void seekAudio(MethodCall call, MethodChannel.Result result) {
        Number position = call.argument("positionMs");
        int positionMs = position == null ? 0 : Math.max(0, position.intValue());
        try {
            if (mediaPlayer != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    mediaPlayer.seekTo(positionMs, MediaPlayer.SEEK_CLOSEST);
                } else {
                    mediaPlayer.seekTo(positionMs);
                }
            }
            result.success(playerState());
        } catch (Exception exception) {
            result.error("seek_failed", "Unable to seek audio.", null);
        }
    }

    private void setPlayerVolume(MethodCall call, MethodChannel.Result result) {
        Number volume = call.argument("volume");
        if (volume != null) {
            playerVolume = Math.max(0f, Math.min(1f, volume.floatValue()));
        }
        if (mediaPlayer != null) {
            mediaPlayer.setVolume(playerVolume, playerVolume);
        }
        result.success(playerState());
    }

    private Map<String, Object> playerState() {
        Map<String, Object> state = new HashMap<>();
        state.put("path", playerPath);
        state.put("volume", playerVolume);
        state.put("isPlaying", false);
        state.put("positionMs", 0);
        state.put("durationMs", 0);

        if (mediaPlayer == null) {
            return state;
        }

        try {
            state.put("isPlaying", mediaPlayer.isPlaying());
            state.put("positionMs", mediaPlayer.getCurrentPosition());
            state.put("durationMs", mediaPlayer.getDuration());
        } catch (Exception ignored) {
        }
        return state;
    }

    private void sendPlayerEvent(Map<String, Object> event) {
        if (playerEventSink == null) {
            return;
        }
        runOnUiThread(() -> {
            if (playerEventSink != null) {
                playerEventSink.success(event);
            }
        });
    }

    private void releasePlayer() {
        if (mediaPlayer == null) {
            playerPath = null;
            return;
        }
        try {
            mediaPlayer.setOnCompletionListener(null);
            mediaPlayer.stop();
        } catch (Exception ignored) {
        }
        try {
            mediaPlayer.release();
        } catch (Exception ignored) {
        }
        mediaPlayer = null;
        playerPath = null;
    }

    private String readTextFile(File file) throws IOException {
        byte[] bytes = readAllBytes(file);
        if (bytes.length >= 3
                && (bytes[0] & 0xff) == 0xef
                && (bytes[1] & 0xff) == 0xbb
                && (bytes[2] & 0xff) == 0xbf) {
            return new String(bytes, 3, bytes.length - 3, StandardCharsets.UTF_8);
        }
        if (bytes.length >= 2
                && (bytes[0] & 0xff) == 0xff
                && (bytes[1] & 0xff) == 0xfe) {
            return new String(bytes, 2, bytes.length - 2, StandardCharsets.UTF_16LE);
        }
        if (bytes.length >= 2
                && (bytes[0] & 0xff) == 0xfe
                && (bytes[1] & 0xff) == 0xff) {
            return new String(bytes, 2, bytes.length - 2, StandardCharsets.UTF_16BE);
        }

        Charset[] candidates = new Charset[]{
                StandardCharsets.UTF_8,
                Charset.forName("GB18030"),
                StandardCharsets.UTF_16LE,
                StandardCharsets.UTF_16BE
        };
        for (Charset charset : candidates) {
            try {
                CharsetDecoder decoder = charset.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT);
                return decoder.decode(ByteBuffer.wrap(bytes)).toString();
            } catch (CharacterCodingException ignored) {
            }
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    private byte[] readAllBytes(File file) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        FileInputStream input = new FileInputStream(file);
        try {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
            }
        } finally {
            input.close();
        }
        return output.toByteArray();
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

    @Override
    protected void onDestroy() {
        releasePlayer();
        super.onDestroy();
    }
}
