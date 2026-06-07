package com.codex.videoextractor;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import com.yausername.ffmpeg.FFmpeg;
import com.yausername.youtubedl_android.YoutubeDL;
import com.yausername.youtubedl_android.YoutubeDLException;
import com.yausername.youtubedl_android.YoutubeDLRequest;
import com.yausername.youtubedl_android.YoutubeDLResponse;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import kotlin.Unit;
import kotlin.jvm.functions.Function3;

public class MainActivity extends Activity {
    private static final int BRAND = Color.rgb(37, 99, 235);
    private static final int BACKGROUND = Color.rgb(247, 247, 248);
    private static final int CARD = Color.WHITE;
    private static final int TEXT_PRIMARY = Color.rgb(24, 24, 27);
    private static final int TEXT_SECONDARY = Color.rgb(82, 82, 91);
    private static final int REQUEST_WRITE_STORAGE = 701;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private final List<DownloadTask> tasks = new ArrayList<>();
    private final List<HistoryRecord> historyRecords = new ArrayList<>();
    private final List<String> logs = new ArrayList<>();
    private final Map<String, DownloadTask> taskById = new HashMap<>();

    private EditText urlInput;
    private Spinner videoModeSpinner;
    private Spinner audioFormatSpinner;
    private TextView statusText;
    private TextView metadataText;
    private TextView saveText;
    private TextView historyText;
    private TextView logText;
    private RadioGroup formatGroup;
    private LinearLayout queueContainer;
    private Button analyzeButton;
    private Button downloadVideoButton;
    private Button downloadAudioButton;
    private Button downloadImagesButton;
    private Button updateCoreButton;

    private DownloadTask selectedTask;
    private String selectedFormatId;
    private String selectedMode = DownloadMode.BEST.key;
    private String selectedAudioFormat = AudioFormat.M4A.key;
    private boolean coreReady = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildContentView());
        loadHistory();
        renderHistory();
        renderLogs();
        applyIncomingText(getIntent());
        requestStorageIfNeeded();
        initializeCore();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdownNow();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        applyIncomingText(intent);
    }

    private View buildContentView() {
        ScrollView scrollView = new ScrollView(this);
        scrollView.setFillViewport(true);
        scrollView.setBackgroundColor(BACKGROUND);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(18), dp(18), dp(28));
        scrollView.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(0, 0, 0, dp(10));
        TextView title = text("视频提取器", 30, true, TEXT_PRIMARY);
        TextView subtitle = text("粘贴公开视频链接，分析后下载视频、音频或图片；完成后自动保存到系统相册/媒体库。", 14, false, TEXT_SECONDARY);
        header.addView(title);
        header.addView(subtitle);
        root.addView(header);

        root.addView(urlCard());
        root.addView(destinationCard());
        root.addView(formatCard());
        root.addView(queueCard());
        root.addView(historyCard());
        root.addView(logCard());

        return scrollView;
    }

    private View urlCard() {
        LinearLayout card = card();
        LinearLayout bar = row();
        TextView heading = text("视频链接", 18, true, TEXT_PRIMARY);
        analyzeButton = button("分析链接");
        analyzeButton.setOnClickListener(v -> analyzeLinks());
        bar.addView(heading, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        bar.addView(analyzeButton);
        card.addView(bar);

        urlInput = new EditText(this);
        urlInput.setMinLines(4);
        urlInput.setGravity(Gravity.TOP | Gravity.START);
        urlInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        urlInput.setSingleLine(false);
        urlInput.setHint("每行一个链接，例如 https://www.youtube.com/watch?v=...");
        urlInput.setTextColor(TEXT_PRIMARY);
        urlInput.setHintTextColor(Color.rgb(150, 150, 160));
        urlInput.setBackgroundColor(Color.rgb(245, 245, 246));
        urlInput.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        inputParams.topMargin = dp(12);
        card.addView(urlInput, inputParams);
        return card;
    }

    private View destinationCard() {
        LinearLayout card = card();
        TextView heading = text("保存位置", 18, true, TEXT_PRIMARY);
        saveText = text("视频保存到 Movies/视频提取器，图片保存到 Pictures/视频提取器，音频保存到 Music/视频提取器。", 14, false, TEXT_SECONDARY);
        card.addView(heading);
        card.addView(saveText);
        return card;
    }

    private View formatCard() {
        LinearLayout card = card();
        card.addView(text("格式选择", 18, true, TEXT_PRIMARY));

        metadataText = text("等待分析。", 14, false, TEXT_SECONDARY);
        metadataText.setPadding(0, dp(8), 0, dp(8));
        card.addView(metadataText);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.addView(label("视频规格"));
        videoModeSpinner = new Spinner(this);
        videoModeSpinner.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, DownloadMode.labels()));
        videoModeSpinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                selectedMode = DownloadMode.values()[position].key;
                updateActionButtons();
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {
            }
        });
        controls.addView(videoModeSpinner);

        controls.addView(label("音频格式"));
        audioFormatSpinner = new Spinner(this);
        audioFormatSpinner.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, AudioFormat.labels()));
        audioFormatSpinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                selectedAudioFormat = AudioFormat.values()[position].key;
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {
            }
        });
        controls.addView(audioFormatSpinner);
        card.addView(controls);

        TextView formatHeading = label("可用格式");
        formatHeading.setPadding(0, dp(12), 0, 0);
        card.addView(formatHeading);
        HorizontalScrollView scroller = new HorizontalScrollView(this);
        formatGroup = new RadioGroup(this);
        formatGroup.setOrientation(RadioGroup.VERTICAL);
        scroller.addView(formatGroup);
        card.addView(scroller);

        LinearLayout actions = row();
        actions.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        downloadImagesButton = button("下载图片");
        downloadAudioButton = button("仅音频");
        downloadVideoButton = button("下载视频");
        downloadImagesButton.setOnClickListener(v -> startSelectedDownload(DownloadKind.IMAGES));
        downloadAudioButton.setOnClickListener(v -> startSelectedDownload(DownloadKind.AUDIO));
        downloadVideoButton.setOnClickListener(v -> startSelectedDownload(DownloadKind.VIDEO));
        actions.addView(downloadImagesButton);
        actions.addView(downloadAudioButton);
        actions.addView(downloadVideoButton);
        LinearLayout.LayoutParams actionParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        actionParams.topMargin = dp(14);
        card.addView(actions, actionParams);
        updateActionButtons();
        return card;
    }

    private View queueCard() {
        LinearLayout card = card();
        LinearLayout bar = row();
        bar.addView(text("下载队列", 18, true, TEXT_PRIMARY), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        statusText = text("初始化中", 13, false, TEXT_SECONDARY);
        bar.addView(statusText);
        card.addView(bar);
        queueContainer = new LinearLayout(this);
        queueContainer.setOrientation(LinearLayout.VERTICAL);
        queueContainer.setPadding(0, dp(10), 0, 0);
        card.addView(queueContainer);
        renderQueue();
        return card;
    }

    private View historyCard() {
        LinearLayout card = card();
        LinearLayout bar = row();
        bar.addView(text("历史记录", 18, true, TEXT_PRIMARY), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        Button clear = button("清理历史");
        clear.setOnClickListener(v -> clearHistory());
        bar.addView(clear);
        card.addView(bar);
        historyText = text("", 13, false, TEXT_SECONDARY);
        historyText.setPadding(0, dp(8), 0, 0);
        card.addView(historyText);
        return card;
    }

    private View logCard() {
        LinearLayout card = card();
        LinearLayout bar = row();
        bar.addView(text("日志", 18, true, TEXT_PRIMARY), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        updateCoreButton = button("更新核心");
        updateCoreButton.setOnClickListener(v -> updateYtdlpCore());
        bar.addView(updateCoreButton);
        card.addView(bar);
        logText = text("", 12, false, TEXT_SECONDARY);
        logText.setPadding(0, dp(8), 0, 0);
        card.addView(logText);
        return card;
    }

    private void initializeCore() {
        setBusy(true, "正在初始化下载核心...");
        executor.execute(() -> {
            try {
                YoutubeDL.getInstance().init(this);
                FFmpeg.getInstance().init(this);
                coreReady = true;
                log("下载核心初始化完成，yt-dlp " + safeText(YoutubeDL.getInstance().versionName(this), "ready"));
                runOnUi(() -> setBusy(false, "就绪"));
            } catch (Exception e) {
                coreReady = false;
                log("下载核心初始化失败：" + e.getMessage());
                runOnUi(() -> {
                    setBusy(false, "初始化失败");
                    showError("下载核心初始化失败：" + e.getMessage());
                });
            }
        });
    }

    private void updateYtdlpCore() {
        if (!coreReady) {
            showError("下载核心还没有初始化完成。");
            return;
        }
        setBusy(true, "正在更新 yt-dlp...");
        executor.execute(() -> {
            try {
                YoutubeDL.UpdateStatus result = YoutubeDL.getInstance().updateYoutubeDL(this, YoutubeDL.UpdateChannel._STABLE);
                log("yt-dlp 更新结果：" + result);
                runOnUi(() -> setBusy(false, "更新完成"));
            } catch (Exception e) {
                log("yt-dlp 更新失败：" + e.getMessage());
                runOnUi(() -> {
                    setBusy(false, "更新失败");
                    showError("更新失败：" + e.getMessage());
                });
            }
        });
    }

    private void analyzeLinks() {
        if (!coreReady) {
            showError("下载核心还在初始化，请稍等。");
            return;
        }
        String input = urlInput.getText().toString().trim();
        if (input.isEmpty()) {
            showError("请先输入一个有效链接。");
            return;
        }
        String[] lines = input.split("\\r?\\n");
        for (String line : lines) {
            String raw = line.trim();
            if (raw.isEmpty()) {
                continue;
            }
            if (!isHttpUrl(raw)) {
                showError("只支持 http 或 https 链接：" + raw);
                continue;
            }
            DownloadTask task = new DownloadTask(raw);
            task.status = TaskStatus.ANALYZING;
            addTask(task);
            executor.execute(() -> analyzeSingle(task));
        }
    }

    private void analyzeSingle(DownloadTask task) {
        try {
            log("开始分析：" + task.url);
            JSONObject json = fetchMetadataJson(task.url);
            MediaMetadata metadata = parseMetadata(json, task.url);
            task.metadata = metadata;
            task.title = metadata.title;
            task.platform = metadata.platform;
            task.status = TaskStatus.READY;
            selectedTask = task;
            selectedFormatId = firstFormatId(metadata.formats);
            log("分析完成：" + metadata.title);
            runOnUi(() -> {
                selectTask(task);
                renderQueue();
            });
        } catch (Exception e) {
            task.status = TaskStatus.FAILED;
            task.errorMessage = friendlyError(e, "当前链接无法解析。");
            log("分析失败：" + task.url + " " + task.errorMessage);
            appendHistory(task, "分析失败");
            runOnUi(() -> {
                selectTask(task);
                renderQueue();
                showError(task.errorMessage);
            });
        }
    }

    private JSONObject fetchMetadataJson(String url) throws Exception {
        YoutubeDLRequest request = new YoutubeDLRequest(url);
        request.addOption("-J");
        request.addOption("--no-playlist");
        YoutubeDLResponse response = YoutubeDL.getInstance().execute(request, null, false, null);
        return new JSONObject(response.getOut());
    }

    private void startSelectedDownload(DownloadKind kind) {
        DownloadTask task = selectedTask;
        if (task == null || task.metadata == null || task.status == TaskStatus.ANALYZING) {
            showError(kind == DownloadKind.IMAGES ? "请先分析一个有效的小红书图文链接。" : "请先分析一个有效链接。");
            return;
        }
        if (kind == DownloadKind.IMAGES && task.metadata.imageUrls.isEmpty()) {
            showError("没有找到可下载图片。");
            return;
        }
        if (task.status == TaskStatus.DOWNLOADING || task.status == TaskStatus.CONVERTING) {
            showError("当前任务正在下载。");
            return;
        }
        task.kind = kind;
        task.selectedMode = selectedMode;
        task.selectedFormatId = selectedMode.equals(DownloadMode.CUSTOM.key) ? selectedFormatId : null;
        task.selectedAudioFormat = selectedAudioFormat;
        startDownload(task, false);
    }

    private void startDownload(DownloadTask task, boolean resuming) {
        if (!coreReady) {
            showError("下载核心还没有初始化完成。");
            return;
        }
        if (task.metadata == null) {
            showError("请先分析链接。");
            return;
        }
        task.status = TaskStatus.DOWNLOADING;
        task.errorMessage = null;
        task.progress = 0;
        task.progressText = "0%";
        task.processId = "task-" + task.id;
        if (task.outputBase == null || task.outputBase.isEmpty()) {
            task.outputBase = uniqueBaseName(task.metadata.title);
        }
        log((resuming ? "继续下载：" : "开始下载：") + task.title);
        renderQueue();
        executor.execute(() -> {
            switch (task.kind) {
                case VIDEO:
                    downloadVideo(task);
                    break;
                case AUDIO:
                    downloadAudio(task);
                    break;
                case IMAGES:
                    downloadImages(task);
                    break;
            }
        });
    }

    private void downloadVideo(DownloadTask task) {
        File workDir = workDir(Environment.DIRECTORY_MOVIES);
        YoutubeDLRequest request = baseDownloadRequest(task.url, workDir, task.outputBase);
        request.addOption("-f", formatSelector(task));
        request.addOption("--merge-output-format", "mp4");
        executeMediaDownload(task, request, workDir, DownloadKind.VIDEO);
    }

    private void downloadAudio(DownloadTask task) {
        File workDir = workDir(Environment.DIRECTORY_MUSIC);
        YoutubeDLRequest request = baseDownloadRequest(task.url, workDir, task.outputBase);
        request.addOption("-f", "bestaudio/b");
        request.addOption("-x");
        request.addOption("--audio-format", task.selectedAudioFormat);
        request.addOption("--audio-quality", "0");
        executeMediaDownload(task, request, workDir, DownloadKind.AUDIO);
    }

    private YoutubeDLRequest baseDownloadRequest(String url, File workDir, String outputBase) {
        if (!workDir.exists()) {
            workDir.mkdirs();
        }
        YoutubeDLRequest request = new YoutubeDLRequest(url);
        request.addOption("--newline");
        request.addOption("--no-playlist");
        request.addOption("--windows-filenames");
        request.addOption("--trim-filenames", "180");
        request.addOption("--no-overwrites");
        request.addOption("--continue");
        request.addOption("--print", "after_move:filepath");
        request.addOption("-P", workDir.getAbsolutePath());
        request.addOption("-o", outputBase + ".%(ext)s");
        return request;
    }

    private void executeMediaDownload(DownloadTask task, YoutubeDLRequest request, File workDir, DownloadKind kind) {
        try {
            Function3<Float, Long, String, Unit> callback = (progress, eta, line) -> {
                if (progress != null && progress >= 0) {
                    task.progress = Math.max(0, Math.min(100, progress));
                    task.progressText = String.format(Locale.US, "%.1f%%", task.progress);
                    task.etaText = eta != null && eta > 0 ? eta + "s" : "";
                    runOnUi(this::renderQueue);
                }
                if (line != null && line.contains("ffmpeg")) {
                    task.status = TaskStatus.CONVERTING;
                    runOnUi(this::renderQueue);
                }
                return Unit.INSTANCE;
            };
            YoutubeDLResponse response = YoutubeDL.getInstance().execute(request, task.processId, false, callback);
            File output = finalOutputFile(response, workDir, task.outputBase);
            if (output == null || !output.exists()) {
                throw new IOException("没有找到下载完成的文件。");
            }
            Uri savedUri = saveFileToMediaStore(output, kind, output.getName());
            task.status = TaskStatus.COMPLETED;
            task.progress = 100;
            task.progressText = "100%";
            task.outputUri = savedUri.toString();
            task.errorMessage = null;
            appendHistory(task, kind == DownloadKind.AUDIO ? "仅音频 " + task.selectedAudioFormat : modeDisplayName(task.selectedMode));
            log("保存完成：" + task.outputUri);
            runOnUi(() -> {
                renderQueue();
                renderHistory();
                Toast.makeText(this, "已保存到系统媒体库", Toast.LENGTH_LONG).show();
            });
        } catch (YoutubeDL.CanceledException e) {
            if (task.status != TaskStatus.PAUSED) {
                task.status = TaskStatus.CANCELLED;
                task.errorMessage = "已取消";
                appendHistory(task, "已取消");
            }
            log("任务停止：" + task.title);
            runOnUi(() -> {
                renderQueue();
                renderHistory();
            });
        } catch (Exception e) {
            task.status = TaskStatus.FAILED;
            task.errorMessage = friendlyError(e, kind == DownloadKind.AUDIO ? "音频提取失败。" : "视频下载失败。");
            appendHistory(task, task.errorMessage);
            log("下载失败：" + task.errorMessage);
            runOnUi(() -> {
                renderQueue();
                renderHistory();
                showError(task.errorMessage);
            });
        }
    }

    private void downloadImages(DownloadTask task) {
        try {
            File dir = workDir(Environment.DIRECTORY_PICTURES);
            if (!dir.exists()) {
                dir.mkdirs();
            }
            int total = task.metadata.imageUrls.size();
            int success = 0;
            for (int i = 0; i < total; i++) {
                if (task.status == TaskStatus.PAUSED || task.status == TaskStatus.CANCELLED) {
                    throw new YoutubeDL.CanceledException();
                }
                String imageUrl = task.metadata.imageUrls.get(i);
                try {
                    File temp = downloadImageToTemp(imageUrl, dir, i + 1, task.title);
                    Uri saved = saveFileToMediaStore(temp, DownloadKind.IMAGES, temp.getName());
                    success++;
                    task.outputUri = saved.toString();
                    task.progress = (success * 100f) / total;
                    task.progressText = String.format(Locale.US, "%.0f%%", task.progress);
                    runOnUi(this::renderQueue);
                } catch (Exception e) {
                    log("图片下载失败：" + imageUrl + " " + e.getMessage());
                }
            }
            if (success == 0) {
                throw new IOException("没有图片保存成功。");
            }
            task.status = TaskStatus.COMPLETED;
            task.progress = 100;
            task.progressText = "100%";
            appendHistory(task, "小红书图文图片 " + success + "张");
            log("图片保存完成：" + success + "张");
            runOnUi(() -> {
                renderQueue();
                renderHistory();
                Toast.makeText(this, "图片已保存到相册", Toast.LENGTH_LONG).show();
            });
        } catch (YoutubeDL.CanceledException e) {
            if (task.status != TaskStatus.PAUSED) {
                task.status = TaskStatus.CANCELLED;
                task.errorMessage = "已取消";
            }
            runOnUi(this::renderQueue);
        } catch (Exception e) {
            task.status = TaskStatus.FAILED;
            task.errorMessage = friendlyError(e, "图片下载失败。");
            appendHistory(task, "图片下载失败");
            log("图片下载失败：" + task.errorMessage);
            runOnUi(() -> {
                renderQueue();
                renderHistory();
                showError(task.errorMessage);
            });
        }
    }

    private File downloadImageToTemp(String imageUrl, File dir, int index, String title) throws IOException {
        URL url = new URL(imageUrl);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(20000);
        connection.setReadTimeout(30000);
        connection.setRequestProperty("User-Agent", "Mozilla/5.0");
        int code = connection.getResponseCode();
        if (code < 200 || code >= 300) {
            throw new IOException("图片服务器返回 " + code);
        }
        String extension = extensionFrom(imageUrl, connection.getContentType(), "jpg");
        File out = uniqueFile(dir, String.format(Locale.US, "%s_image_%03d.%s", sanitizeFileName(title), index, extension));
        try (InputStream input = new BufferedInputStream(connection.getInputStream());
             OutputStream output = new BufferedOutputStream(new FileOutputStream(out))) {
            copy(input, output);
        } finally {
            connection.disconnect();
        }
        return out;
    }

    private Uri saveFileToMediaStore(File source, DownloadKind kind, String displayName) throws IOException {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, displayName);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mimeType(displayName, kind));
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            Uri collection;
            if (kind == DownloadKind.IMAGES) {
                collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/视频提取器");
            } else if (kind == DownloadKind.AUDIO) {
                collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
                values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/视频提取器");
            } else {
                collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
                values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/视频提取器");
            }
            Uri uri = resolver.insert(collection, values);
            if (uri == null) {
                throw new IOException("无法创建媒体库条目。");
            }
            try (InputStream input = new BufferedInputStream(new FileInputStream(source));
                 OutputStream output = new BufferedOutputStream(resolver.openOutputStream(uri))) {
                if (output == null) {
                    throw new IOException("无法写入媒体库。");
                }
                copy(input, output);
            }
            values.clear();
            values.put(MediaStore.MediaColumns.IS_PENDING, 0);
            resolver.update(uri, values, null, null);
            return uri;
        }

        String publicType = kind == DownloadKind.IMAGES
                ? Environment.DIRECTORY_PICTURES
                : kind == DownloadKind.AUDIO ? Environment.DIRECTORY_MUSIC : Environment.DIRECTORY_MOVIES;
        File publicDir = new File(Environment.getExternalStoragePublicDirectory(publicType), "视频提取器");
        if (!publicDir.exists() && !publicDir.mkdirs()) {
            throw new IOException("无法创建相册目录。");
        }
        File destination = uniqueFile(publicDir, displayName);
        try (InputStream input = new BufferedInputStream(new FileInputStream(source));
             OutputStream output = new BufferedOutputStream(new FileOutputStream(destination))) {
            copy(input, output);
        }
        MediaScannerConnection.scanFile(this, new String[]{destination.getAbsolutePath()}, new String[]{mimeType(displayName, kind)}, null);
        return Uri.fromFile(destination);
    }

    private File finalOutputFile(YoutubeDLResponse response, File workDir, String outputBase) {
        String combined = response.getOut() + "\n" + response.getErr();
        String[] lines = combined.split("\\r?\\n");
        File last = null;
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.startsWith(workDir.getAbsolutePath())) {
                File candidate = new File(trimmed);
                if (candidate.exists()) {
                    last = candidate;
                }
            }
        }
        if (last != null) {
            return last;
        }
        File[] files = workDir.listFiles();
        if (files == null) {
            return null;
        }
        long newest = Long.MIN_VALUE;
        for (File file : files) {
            if (file.isFile() && file.getName().startsWith(outputBase) && file.lastModified() > newest) {
                newest = file.lastModified();
                last = file;
            }
        }
        return last;
    }

    private String formatSelector(DownloadTask task) {
        if (DownloadMode.VIDEO_1080.key.equals(task.selectedMode)) {
            return "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b";
        }
        if (DownloadMode.VIDEO_720.key.equals(task.selectedMode)) {
            return "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b";
        }
        if (DownloadMode.VIDEO_480.key.equals(task.selectedMode)) {
            return "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b";
        }
        if (DownloadMode.CUSTOM.key.equals(task.selectedMode) && task.selectedFormatId != null && !task.selectedFormatId.isEmpty()) {
            return task.selectedFormatId + "+ba/" + task.selectedFormatId + "/b";
        }
        return "bv*+ba/b";
    }

    private MediaMetadata parseMetadata(JSONObject json, String fallbackUrl) {
        MediaMetadata metadata = new MediaMetadata();
        metadata.id = safeJsonString(json, "id", UUID.randomUUID().toString());
        metadata.title = safeJsonString(json, "title", "video_" + timestamp());
        metadata.author = safeJsonString(json, "uploader", safeJsonString(json, "channel", ""));
        metadata.duration = json.optDouble("duration", 0);
        metadata.platform = detectPlatform(safeJsonString(json, "webpage_url", fallbackUrl));

        Set<String> seen = new HashSet<>();
        appendImageUrl(safeJsonString(json, "thumbnail", ""), metadata.imageUrls, seen);
        collectImageUrls(json, metadata.imageUrls, seen);

        JSONArray formats = json.optJSONArray("formats");
        if (formats != null) {
            for (int i = 0; i < formats.length(); i++) {
                JSONObject object = formats.optJSONObject(i);
                if (object == null) {
                    continue;
                }
                String formatId = safeJsonString(object, "format_id", "");
                if (formatId.isEmpty()) {
                    continue;
                }
                MediaFormat format = new MediaFormat();
                format.formatId = formatId;
                format.extensionName = safeJsonString(object, "ext", "-");
                format.resolution = safeJsonString(object, "resolution", "");
                format.width = object.optInt("width", 0);
                format.height = object.optInt("height", 0);
                format.fps = object.optDouble("fps", 0);
                format.fileSize = object.optLong("filesize", 0);
                format.approxFileSize = object.optLong("filesize_approx", 0);
                format.videoCodec = safeJsonString(object, "vcodec", "none");
                format.audioCodec = safeJsonString(object, "acodec", "none");
                format.audioBitrate = object.optDouble("abr", 0);
                format.totalBitrate = object.optDouble("tbr", 0);
                format.formatNote = safeJsonString(object, "format_note", "");
                metadata.formats.add(format);
            }
        }
        return metadata;
    }

    private void collectImageUrls(Object value, List<String> output, Set<String> seen) {
        if (output.size() >= 80 || value == null || value == JSONObject.NULL) {
            return;
        }
        if (value instanceof String) {
            appendImageUrl((String) value, output, seen);
            return;
        }
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            JSONArray names = object.names();
            if (names == null) {
                return;
            }
            for (int i = 0; i < names.length(); i++) {
                collectImageUrls(object.opt(names.optString(i)), output, seen);
                if (output.size() >= 80) {
                    return;
                }
            }
            return;
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                collectImageUrls(array.opt(i), output, seen);
                if (output.size() >= 80) {
                    return;
                }
            }
        }
    }

    private void appendImageUrl(String value, List<String> output, Set<String> seen) {
        if (value == null || value.isEmpty()) {
            return;
        }
        Uri uri = Uri.parse(value);
        String scheme = uri.getScheme();
        if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) {
            return;
        }
        String lower = value.toLowerCase(Locale.US);
        String path = uri.getPath() == null ? "" : uri.getPath().toLowerCase(Locale.US);
        boolean likely = path.matches(".*\\.(jpg|jpeg|png|webp|avif|heic|heif)$")
                || lower.contains("imageview")
                || lower.contains("sns-img")
                || lower.contains("xhscdn")
                || lower.contains("xhs");
        if (!likely || seen.contains(value)) {
            return;
        }
        seen.add(value);
        output.add(value);
    }

    private void pauseTask(DownloadTask task) {
        if (task.status != TaskStatus.DOWNLOADING && task.status != TaskStatus.CONVERTING) {
            return;
        }
        task.status = TaskStatus.PAUSED;
        if (task.processId != null) {
            YoutubeDL.getInstance().destroyProcessById(task.processId);
        }
        log("已暂停：" + task.title);
        renderQueue();
    }

    private void resumeTask(DownloadTask task) {
        if (task.status != TaskStatus.PAUSED) {
            return;
        }
        startDownload(task, true);
    }

    private void cancelTask(DownloadTask task) {
        if (task.status == TaskStatus.DOWNLOADING || task.status == TaskStatus.CONVERTING) {
            task.status = TaskStatus.CANCELLED;
            if (task.processId != null) {
                YoutubeDL.getInstance().destroyProcessById(task.processId);
            }
        } else {
            task.status = TaskStatus.CANCELLED;
        }
        task.errorMessage = "已取消";
        log("已取消：" + task.title);
        renderQueue();
    }

    private void selectTask(DownloadTask task) {
        selectedTask = task;
        if (task.selectedMode != null) {
            selectedMode = task.selectedMode;
            videoModeSpinner.setSelection(DownloadMode.indexOf(selectedMode));
        }
        if (task.selectedAudioFormat != null) {
            selectedAudioFormat = task.selectedAudioFormat;
            audioFormatSpinner.setSelection(AudioFormat.indexOf(selectedAudioFormat));
        }
        if (task.selectedFormatId != null) {
            selectedFormatId = task.selectedFormatId;
        } else if (task.metadata != null) {
            selectedFormatId = firstFormatId(task.metadata.formats);
        }
        renderMetadata();
        renderFormats();
        updateActionButtons();
    }

    private void addTask(DownloadTask task) {
        tasks.add(0, task);
        taskById.put(task.id, task);
        selectedTask = task;
        renderQueue();
    }

    private void renderMetadata() {
        if (selectedTask == null || selectedTask.metadata == null) {
            metadataText.setText("等待分析。");
            return;
        }
        MediaMetadata metadata = selectedTask.metadata;
        String images = metadata.imageUrls.isEmpty() ? "" : "\n图片：" + metadata.imageUrls.size() + " 张";
        metadataText.setText(
                "标题：" + metadata.title +
                        "\n平台：" + metadata.platform +
                        "\n作者：" + safeText(metadata.author, "-") +
                        "\n时长：" + metadata.displayDuration() +
                        images);
    }

    private void renderFormats() {
        formatGroup.removeAllViews();
        if (selectedTask == null || selectedTask.metadata == null || selectedTask.metadata.formats.isEmpty()) {
            RadioButton empty = new RadioButton(this);
            empty.setText("暂无格式列表");
            empty.setEnabled(false);
            formatGroup.addView(empty);
            return;
        }
        List<MediaFormat> formats = new ArrayList<>(selectedTask.metadata.formats);
        Collections.sort(formats, (left, right) -> {
            int heightCompare = Integer.compare(right.height, left.height);
            if (heightCompare != 0) {
                return heightCompare;
            }
            return Double.compare(right.totalBitrate, left.totalBitrate);
        });
        int visibleCount = 0;
        for (MediaFormat format : formats) {
            if ("未知".equals(format.kind())) {
                continue;
            }
            RadioButton button = new RadioButton(this);
            button.setText(format.summary() + "  " + format.codecSummary());
            button.setTextColor(TEXT_PRIMARY);
            button.setTextSize(13);
            button.setSingleLine(false);
            button.setTag(format.formatId);
            button.setOnClickListener(v -> {
                selectedFormatId = String.valueOf(v.getTag());
                if (selectedTask != null) {
                    selectedTask.selectedFormatId = selectedFormatId;
                }
            });
            if (format.formatId.equals(selectedFormatId)) {
                button.setChecked(true);
            }
            formatGroup.addView(button);
            visibleCount++;
            if (visibleCount >= 80) {
                break;
            }
        }
    }

    private void renderQueue() {
        if (queueContainer == null) {
            return;
        }
        queueContainer.removeAllViews();
        if (tasks.isEmpty()) {
            queueContainer.addView(text("暂无任务。分析链接后会加入队列。", 14, false, TEXT_SECONDARY));
            return;
        }
        for (DownloadTask task : tasks) {
            queueContainer.addView(taskRow(task));
        }
    }

    private View taskRow(DownloadTask task) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(12), dp(10), dp(12), dp(10));
        box.setBackgroundColor(task == selectedTask ? Color.rgb(232, 240, 255) : Color.rgb(245, 245, 246));
        LinearLayout.LayoutParams boxParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        boxParams.bottomMargin = dp(10);
        box.setLayoutParams(boxParams);
        box.setOnClickListener(v -> selectTask(task));

        LinearLayout top = row();
        TextView title = text(task.title, 15, true, TEXT_PRIMARY);
        top.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        TextView badge = text(task.status.displayName, 12, true, statusColor(task.status));
        top.addView(badge);
        box.addView(top);

        TextView url = text(task.url, 12, false, TEXT_SECONDARY);
        url.setSingleLine(true);
        url.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        box.addView(url);

        ProgressBar progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(1000);
        progressBar.setProgress(Math.round(task.progress * 10));
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        progressParams.topMargin = dp(8);
        box.addView(progressBar, progressParams);

        String detail = task.progressText;
        if (!task.etaText.isEmpty()) {
            detail += "  剩余 " + task.etaText;
        }
        if (task.outputUri != null) {
            detail += "\n" + task.outputUri;
        }
        if (task.errorMessage != null) {
            detail += "\n" + task.errorMessage;
        }
        box.addView(text(detail, 12, false, task.errorMessage == null ? TEXT_SECONDARY : Color.rgb(185, 28, 28)));

        LinearLayout actions = row();
        actions.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        if (task.status == TaskStatus.DOWNLOADING || task.status == TaskStatus.CONVERTING) {
            Button pause = smallButton("暂停");
            pause.setOnClickListener(v -> pauseTask(task));
            Button cancel = smallButton("取消");
            cancel.setOnClickListener(v -> cancelTask(task));
            actions.addView(pause);
            actions.addView(cancel);
        } else if (task.status == TaskStatus.PAUSED) {
            Button resume = smallButton("继续");
            resume.setOnClickListener(v -> resumeTask(task));
            Button cancel = smallButton("取消");
            cancel.setOnClickListener(v -> cancelTask(task));
            actions.addView(resume);
            actions.addView(cancel);
        }
        if (actions.getChildCount() > 0) {
            box.addView(actions);
        }
        return box;
    }

    private void updateActionButtons() {
        boolean hasReadyTask = selectedTask != null && selectedTask.metadata != null;
        downloadVideoButton.setEnabled(hasReadyTask);
        downloadAudioButton.setEnabled(hasReadyTask);
        downloadImagesButton.setEnabled(hasReadyTask && selectedTask.metadata != null && !selectedTask.metadata.imageUrls.isEmpty());
    }

    private void appendHistory(DownloadTask task, String formatDescription) {
        HistoryRecord record = new HistoryRecord();
        record.title = task.title;
        record.url = task.url;
        record.platform = task.platform;
        record.output = task.outputUri;
        record.formatDescription = formatDescription;
        record.status = task.status.displayName;
        record.createdAt = now();
        historyRecords.add(0, record);
        while (historyRecords.size() > 200) {
            historyRecords.remove(historyRecords.size() - 1);
        }
        saveHistory();
        runOnUi(this::renderHistory);
    }

    private void renderHistory() {
        if (historyText == null) {
            return;
        }
        if (historyRecords.isEmpty()) {
            historyText.setText("暂无历史记录。");
            return;
        }
        StringBuilder builder = new StringBuilder();
        int count = Math.min(30, historyRecords.size());
        for (int i = 0; i < count; i++) {
            HistoryRecord record = historyRecords.get(i);
            builder.append(record.createdAt)
                    .append("  ")
                    .append(record.status)
                    .append("  ")
                    .append(record.formatDescription)
                    .append("\n")
                    .append(record.title)
                    .append("\n")
                    .append(record.output == null ? record.url : record.output)
                    .append("\n\n");
        }
        historyText.setText(builder.toString().trim());
    }

    private void clearHistory() {
        historyRecords.clear();
        File history = historyFile();
        if (history.exists()) {
            File deletedDir = new File(getFilesDir(), "要删除的");
            deletedDir.mkdirs();
            history.renameTo(new File(deletedDir, "history_" + timestamp() + ".json"));
        }
        renderHistory();
        log("历史记录已清理。");
    }

    private void saveHistory() {
        JSONArray array = new JSONArray();
        for (HistoryRecord record : historyRecords) {
            JSONObject object = new JSONObject();
            try {
                object.put("title", record.title);
                object.put("url", record.url);
                object.put("platform", record.platform);
                object.put("output", record.output);
                object.put("formatDescription", record.formatDescription);
                object.put("status", record.status);
                object.put("createdAt", record.createdAt);
                array.put(object);
            } catch (JSONException ignored) {
            }
        }
        try (FileWriter writer = new FileWriter(historyFile(), false)) {
            writer.write(array.toString());
        } catch (IOException e) {
            log("历史保存失败：" + e.getMessage());
        }
    }

    private void loadHistory() {
        File file = historyFile();
        if (!file.exists()) {
            return;
        }
        try {
            JSONArray array = new JSONArray(readFile(file));
            for (int i = 0; i < array.length(); i++) {
                JSONObject object = array.getJSONObject(i);
                HistoryRecord record = new HistoryRecord();
                record.title = object.optString("title");
                record.url = object.optString("url");
                record.platform = object.optString("platform");
                record.output = object.optString("output", null);
                record.formatDescription = object.optString("formatDescription");
                record.status = object.optString("status");
                record.createdAt = object.optString("createdAt");
                historyRecords.add(record);
            }
        } catch (Exception e) {
            log("历史读取失败：" + e.getMessage());
        }
    }

    private void log(String message) {
        String line = now() + "  " + message;
        logs.add(0, line);
        while (logs.size() > 120) {
            logs.remove(logs.size() - 1);
        }
        File logsDir = new File(getFilesDir(), "Logs");
        logsDir.mkdirs();
        try (FileWriter writer = new FileWriter(new File(logsDir, "app.log"), true)) {
            writer.write(line + "\n");
        } catch (IOException ignored) {
        }
        runOnUi(this::renderLogs);
    }

    private void renderLogs() {
        if (logText == null) {
            return;
        }
        if (logs.isEmpty()) {
            logText.setText("暂无日志。");
            return;
        }
        StringBuilder builder = new StringBuilder();
        int count = Math.min(80, logs.size());
        for (int i = 0; i < count; i++) {
            builder.append(logs.get(i)).append("\n");
        }
        logText.setText(builder.toString().trim());
    }

    private void applyIncomingText(Intent intent) {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) {
            return;
        }
        CharSequence shared = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
        if (shared != null && urlInput != null) {
            String current = urlInput.getText().toString();
            String next = current.isEmpty() ? shared.toString() : current + "\n" + shared;
            urlInput.setText(next);
        }
    }

    private void requestStorageIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
                && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQUEST_WRITE_STORAGE);
        }
    }

    private void setBusy(boolean busy, String status) {
        analyzeButton.setEnabled(!busy);
        updateCoreButton.setEnabled(!busy);
        statusText.setText(status);
    }

    private void showError(String message) {
        new AlertDialog.Builder(this)
                .setTitle("提示")
                .setMessage(message)
                .setPositiveButton("知道了", null)
                .show();
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        card.setBackgroundColor(CARD);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, dp(8), 0, dp(10));
        card.setLayoutParams(params);
        return card;
    }

    private LinearLayout row() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }

    private TextView text(String value, int sp, boolean bold, int color) {
        TextView textView = new TextView(this);
        textView.setText(value);
        textView.setTextSize(sp);
        textView.setTextColor(color);
        textView.setLineSpacing(0, 1.08f);
        if (bold) {
            textView.setTypeface(textView.getTypeface(), android.graphics.Typeface.BOLD);
        }
        return textView;
    }

    private TextView label(String value) {
        TextView label = text(value, 13, true, TEXT_SECONDARY);
        label.setPadding(0, dp(10), 0, dp(4));
        return label;
    }

    private Button button(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        return button;
    }

    private Button smallButton(String text) {
        Button button = button(text);
        button.setMinHeight(dp(32));
        button.setMinimumHeight(dp(32));
        button.setPadding(dp(10), 0, dp(10), 0);
        return button;
    }

    private void runOnUi(Runnable runnable) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run();
        } else {
            mainHandler.post(runnable);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private File workDir(String type) {
        File base = getExternalFilesDir(type);
        if (base == null) {
            base = getFilesDir();
        }
        return new File(base, "VideoExtractor");
    }

    private File historyFile() {
        return new File(getFilesDir(), "history.json");
    }

    private String readFile(File file) throws IOException {
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line).append('\n');
            }
        }
        return builder.toString();
    }

    private String uniqueBaseName(String title) {
        String base = sanitizeFileName(title);
        if (base.isEmpty()) {
            base = "video_" + timestamp();
        }
        return base + "_" + UUID.randomUUID().toString().substring(0, 8);
    }

    private File uniqueFile(File dir, String fileName) {
        File candidate = new File(dir, fileName);
        if (!candidate.exists()) {
            return candidate;
        }
        String name = fileName;
        String ext = "";
        int dot = fileName.lastIndexOf('.');
        if (dot > 0) {
            name = fileName.substring(0, dot);
            ext = fileName.substring(dot);
        }
        return new File(dir, name + "_" + timestamp() + ext);
    }

    private String sanitizeFileName(String value) {
        if (value == null) {
            return "";
        }
        String safe = value.replaceAll("[\\\\/:*?\"<>|\\n\\r\\t]+", "_").trim();
        if (safe.length() > 90) {
            safe = safe.substring(0, 90).trim();
        }
        return safe;
    }

    private boolean isHttpUrl(String value) {
        Uri uri = Uri.parse(value);
        String scheme = uri.getScheme();
        return ("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))
                && uri.getHost() != null
                && !uri.getHost().isEmpty();
    }

    private String detectPlatform(String value) {
        String host = Uri.parse(value).getHost();
        if (host == null) {
            return "未知";
        }
        host = host.toLowerCase(Locale.US);
        if (host.contains("youtube.com") || host.contains("youtu.be")) {
            return "YouTube";
        }
        if (host.contains("bilibili.com") || host.contains("b23.tv")) {
            return "Bilibili";
        }
        if (host.contains("xiaohongshu.com") || host.contains("xhslink.com")) {
            return "小红书";
        }
        if (host.contains("douyin.com") || host.contains("iesdouyin.com")) {
            return "抖音";
        }
        return "未知";
    }

    private String firstFormatId(List<MediaFormat> formats) {
        for (MediaFormat format : formats) {
            if (!"未知".equals(format.kind())) {
                return format.formatId;
            }
        }
        return null;
    }

    private String modeDisplayName(String mode) {
        for (DownloadMode item : DownloadMode.values()) {
            if (item.key.equals(mode)) {
                return item.label;
            }
        }
        return "最佳质量";
    }

    private String friendlyError(Exception e, String fallback) {
        String message = e.getMessage();
        if (message == null || message.trim().isEmpty()) {
            return fallback;
        }
        if (message.contains("Unsupported URL")) {
            return "当前链接暂不支持。";
        }
        if (message.contains("Private video") || message.contains("login") || message.contains("Sign in")) {
            return "该链接需要登录或权限，已停止。";
        }
        return message.length() > 260 ? message.substring(0, 260) + "..." : message;
    }

    private int statusColor(TaskStatus status) {
        switch (status) {
            case COMPLETED:
                return Color.rgb(22, 163, 74);
            case FAILED:
                return Color.rgb(220, 38, 38);
            case PAUSED:
            case CANCELLED:
                return Color.rgb(217, 119, 6);
            case ANALYZING:
            case DOWNLOADING:
            case CONVERTING:
                return BRAND;
            default:
                return TEXT_SECONDARY;
        }
    }

    private String mimeType(String name, DownloadKind kind) {
        String lower = name.toLowerCase(Locale.US);
        if (kind == DownloadKind.IMAGES) {
            if (lower.endsWith(".png")) return "image/png";
            if (lower.endsWith(".webp")) return "image/webp";
            if (lower.endsWith(".heic") || lower.endsWith(".heif")) return "image/heic";
            return "image/jpeg";
        }
        if (kind == DownloadKind.AUDIO) {
            if (lower.endsWith(".mp3")) return "audio/mpeg";
            if (lower.endsWith(".wav")) return "audio/wav";
            return "audio/mp4";
        }
        if (lower.endsWith(".webm")) return "video/webm";
        if (lower.endsWith(".mkv")) return "video/x-matroska";
        return "video/mp4";
    }

    private String extensionFrom(String url, String mimeType, String fallback) {
        if (mimeType != null) {
            String type = mimeType.toLowerCase(Locale.US);
            if (type.contains("png")) return "png";
            if (type.contains("webp")) return "webp";
            if (type.contains("avif")) return "avif";
            if (type.contains("heic") || type.contains("heif")) return "heic";
            if (type.contains("jpeg") || type.contains("jpg")) return "jpg";
        }
        String path = Uri.parse(url).getPath();
        if (path != null) {
            int dot = path.lastIndexOf('.');
            if (dot >= 0 && dot < path.length() - 1) {
                String ext = path.substring(dot + 1).toLowerCase(Locale.US);
                if (ext.equals("jpeg")) {
                    return "jpg";
                }
                if (ext.matches("jpg|png|webp|avif|heic|heif")) {
                    return ext;
                }
            }
        }
        return fallback;
    }

    private void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[1024 * 128];
        int read;
        while ((read = input.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
        output.flush();
    }

    private String safeText(String value, String fallback) {
        return value == null || value.trim().isEmpty() ? fallback : value;
    }

    private String safeJsonString(JSONObject object, String key, String fallback) {
        if (object == null || object.isNull(key)) {
            return fallback;
        }
        String value = object.optString(key, fallback);
        return value == null || value.trim().isEmpty() || "null".equalsIgnoreCase(value) ? fallback : value.trim();
    }

    private String now() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date());
    }

    private String timestamp() {
        return new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
    }

    private enum DownloadKind {
        VIDEO,
        AUDIO,
        IMAGES
    }

    private enum TaskStatus {
        ANALYZING("分析中"),
        READY("就绪"),
        DOWNLOADING("下载中"),
        CONVERTING("转换中"),
        PAUSED("已暂停"),
        COMPLETED("已完成"),
        FAILED("失败"),
        CANCELLED("已取消");

        final String displayName;

        TaskStatus(String displayName) {
            this.displayName = displayName;
        }
    }

    private enum DownloadMode {
        BEST("best", "最佳质量"),
        VIDEO_1080("1080", "1080p 或更低"),
        VIDEO_720("720", "720p 或更低"),
        VIDEO_480("480", "480p 或更低"),
        CUSTOM("custom", "自定义格式");

        final String key;
        final String label;

        DownloadMode(String key, String label) {
            this.key = key;
            this.label = label;
        }

        static String[] labels() {
            DownloadMode[] values = values();
            String[] labels = new String[values.length];
            for (int i = 0; i < values.length; i++) {
                labels[i] = values[i].label;
            }
            return labels;
        }

        static int indexOf(String key) {
            DownloadMode[] values = values();
            for (int i = 0; i < values.length; i++) {
                if (values[i].key.equals(key)) {
                    return i;
                }
            }
            return 0;
        }
    }

    private enum AudioFormat {
        M4A("m4a"),
        MP3("mp3"),
        WAV("wav");

        final String key;

        AudioFormat(String key) {
            this.key = key;
        }

        static String[] labels() {
            AudioFormat[] values = values();
            String[] labels = new String[values.length];
            for (int i = 0; i < values.length; i++) {
                labels[i] = values[i].key;
            }
            return labels;
        }

        static int indexOf(String key) {
            AudioFormat[] values = values();
            for (int i = 0; i < values.length; i++) {
                if (values[i].key.equals(key)) {
                    return i;
                }
            }
            return 0;
        }
    }

    private class DownloadTask {
        final String id = UUID.randomUUID().toString();
        final String url;
        String title = "等待分析";
        String platform = "未知";
        TaskStatus status = TaskStatus.READY;
        MediaMetadata metadata;
        String errorMessage;
        float progress = 0f;
        String progressText = "0%";
        String etaText = "";
        String outputUri;
        String selectedMode = DownloadMode.BEST.key;
        String selectedAudioFormat = AudioFormat.M4A.key;
        String selectedFormatId;
        String outputBase;
        String processId;
        DownloadKind kind = DownloadKind.VIDEO;

        DownloadTask(String url) {
            this.url = url;
            this.platform = detectPlatform(url);
        }
    }

    private class MediaMetadata {
        String id;
        String title;
        String author;
        String platform;
        double duration;
        final List<String> imageUrls = new ArrayList<>();
        final List<MediaFormat> formats = new ArrayList<>();

        String displayDuration() {
            if (duration <= 0) {
                return "-";
            }
            int total = (int) Math.round(duration);
            int hours = total / 3600;
            int minutes = (total % 3600) / 60;
            int seconds = total % 60;
            if (hours > 0) {
                return String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds);
            }
            return String.format(Locale.US, "%d:%02d", minutes, seconds);
        }

    }

    private class MediaFormat {
        String formatId;
        String extensionName;
        String resolution;
        int width;
        int height;
        double fps;
        long fileSize;
        long approxFileSize;
        String videoCodec;
        String audioCodec;
        double audioBitrate;
        double totalBitrate;
        String formatNote;

        String summary() {
            String size = displaySize();
            String fpsText = fps > 0 ? String.format(Locale.US, " %.0ffps", fps) : "";
            String heightText = height > 0 ? height + "p" : safeText(resolution, "-");
            return formatId + "  " + heightText + fpsText + "  " + extensionName + "  " + kind() + "  " + size;
        }

        String codecSummary() {
            return "V: " + safeText(videoCodec, "none") + "  A: " + safeText(audioCodec, "none");
        }

        String kind() {
            boolean hasVideo = videoCodec != null && !videoCodec.equals("none");
            boolean hasAudio = audioCodec != null && !audioCodec.equals("none");
            if (hasVideo && hasAudio) return "视频+音频";
            if (hasVideo) return "视频";
            if (hasAudio) return "音频";
            return "未知";
        }

        String displaySize() {
            long size = fileSize > 0 ? fileSize : approxFileSize;
            if (size <= 0) {
                return "-";
            }
            double mb = size / 1024.0 / 1024.0;
            if (mb >= 1024) {
                return String.format(Locale.US, "%.2fGB", mb / 1024.0);
            }
            return String.format(Locale.US, "%.1fMB", mb);
        }
    }

    private static class HistoryRecord {
        String title;
        String url;
        String platform;
        String output;
        String formatDescription;
        String status;
        String createdAt;
    }
}
