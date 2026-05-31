package com.foobnix.tts;

import android.media.MediaPlayer;
import android.speech.tts.TextToSpeech;

import com.foobnix.LibreraApp;
import com.foobnix.android.utils.LOG;
import com.foobnix.model.AppState;

import org.greenrobot.eventbus.EventBus;

import java.io.File;
import java.util.HashMap;
import java.util.LinkedList;

public class TTSPreloadTask {

    private static final String TAG = "TTSPreloadTask";
    private TextToSpeech tts;
    private final LinkedList<Sentence> queue = new LinkedList<>();
    private volatile MediaPlayer currentPlayer;
    private volatile boolean isPlaying = false;
    private volatile boolean isStopped = false;

    public interface PlaybackListener {
        void onSentenceStart(String utteranceId);
        void onSentenceDone(String utteranceId);
        void onError(String utteranceId);
    }

    private PlaybackListener listener;

    public static class Sentence {
        public String text;
        public String utteranceId;
        public File wavFile;
        public boolean isSynthesized = false;
        public boolean isSilence = false;
        public long silenceDuration = 0;
        public boolean synthesisTriggered = false;
    }

    public TTSPreloadTask(TextToSpeech tts, PlaybackListener listener) {
        this.tts = tts;
        this.listener = listener;
    }

    public void addSilence(long duration, String utteranceId) {
        Sentence s = new Sentence();
        s.isSilence = true;
        s.silenceDuration = duration;
        s.utteranceId = utteranceId;
        synchronized (queue) {
            queue.add(s);
        }
        checkPlay();
    }

    public void addSentence(String text, String utteranceId) {
        Sentence s = new Sentence();
        s.text = text;
        s.utteranceId = utteranceId;
        s.wavFile = new File(LibreraApp.context.getCacheDir(), "tts_" + utteranceId.replaceAll("[^a-zA-Z0-9_-]", "") + ".wav");
        synchronized (queue) {
            queue.add(s);
        }
        synthesizeNext();
    }

    private void postStats() {
        int pending = 0;
        int synthesized = 0;
        int playing = isPlaying ? 1 : 0;
        synchronized (queue) {
            for (Sentence s : queue) {
                if (s.isSilence) continue;
                if (s.isSynthesized) {
                    synthesized++;
                } else {
                    pending++;
                }
            }
        }
        EventBus.getDefault().post(new TtsPreloadStats(pending, synthesized, playing));
    }

    private void synthesizeNext() {
        if (isStopped) return;
        int activeOrReady = 0;
        Sentence toSynth = null;
        synchronized (queue) {
            for (Sentence s : queue) {
                if (!s.isSilence && (s.isSynthesized || s.synthesisTriggered)) {
                    activeOrReady++;
                }
            }
            if (activeOrReady >= AppState.get().ttsPrecomputeLines) {
                postStats();
                return;
            }
            for (Sentence s : queue) {
                if (!s.isSilence && !s.synthesisTriggered) {
                    toSynth = s;
                    break;
                }
            }
        }
        if (toSynth != null) {
            synchronized (queue) {
                if (toSynth.synthesisTriggered || toSynth.isSynthesized) {
                    postStats();
                    return;
                }
                toSynth.synthesisTriggered = true;
            }
            HashMap<String, String> map = new HashMap<>();
            map.put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "SYNTH_" + toSynth.utteranceId);
            LOG.d(TAG, "Triggering synthesis for " + toSynth.utteranceId);
            tts.synthesizeToFile(toSynth.text, map, toSynth.wavFile.getAbsolutePath());
        }
        postStats();
    }

    public void onSynthesizeDone(String synthUtteranceId) {
        if (isStopped) return;
        String utteranceId = synthUtteranceId.replace("SYNTH_", "");
        LOG.d(TAG, "Synthesis done for " + utteranceId);
        synchronized (queue) {
            for (Sentence s : queue) {
                if (s.utteranceId.equals(utteranceId)) {
                    s.isSynthesized = true;
                    break;
                }
            }
        }
        postStats();
        checkPlay();
        synthesizeNext(); // try to synthesize the next one
    }

    private void checkPlay() {
        if (isStopped) return;
        if (isPlaying) return;

        Sentence next = null;
        synchronized (queue) {
            if (!queue.isEmpty()) {
                next = queue.peek();
            }
        }

        if (next == null) return;

        if (next.isSilence) {
            isPlaying = true;
            postStats();
            synchronized (queue) {
                queue.poll();
            }
            if (listener != null) listener.onSentenceStart(next.utteranceId);
            final String uId = next.utteranceId;
            final long sleepTime = next.silenceDuration;
            new Thread(() -> {
                try {
                    Thread.sleep(sleepTime);
                } catch (InterruptedException e) { }
                if (isStopped) return;
                isPlaying = false;
                if (listener != null) listener.onSentenceDone(uId);
                checkPlay();
            }).start();
        } else if (next.isSynthesized) {
            isPlaying = true;
            postStats();
            synchronized (queue) {
                queue.poll();
            }
            playSentence(next);
        }
    }

    private void playSentence(final Sentence s) {
        if (isStopped) return;
        try {
            currentPlayer = new MediaPlayer();
            currentPlayer.setDataSource(s.wavFile.getAbsolutePath());

            // Gapless playback can be problematic without complex state tracking,
            // because nextPlayer starts automatically and we must track its state.
            // Using standard sequential playback here; gapless is mostly achieved
            // by having the audio file already on disk, so prepare() is nearly instant.
            
            currentPlayer.prepare();
            currentPlayer.setOnCompletionListener(mp -> {
                if (isStopped) return;
                mp.release();
                currentPlayer = null;
                isPlaying = false;
                if (listener != null) listener.onSentenceDone(s.utteranceId);
                s.wavFile.delete(); // cleanup
                checkPlay();
                synthesizeNext(); // fetch more
            });
            currentPlayer.setOnErrorListener((mp, what, extra) -> {
                mp.release();
                currentPlayer = null;
                isPlaying = false;
                if (listener != null) listener.onError(s.utteranceId);
                checkPlay();
                synthesizeNext(); // fetch more
                return true;
            });
            if (listener != null) listener.onSentenceStart(s.utteranceId);
            currentPlayer.start();
        } catch (Exception e) {
            LOG.e(e);
            isPlaying = false;
            if (listener != null) listener.onError(s.utteranceId);
            checkPlay();
            synthesizeNext();
        }
    }

    public void stop() {
        isStopped = true;
        if (currentPlayer != null) {
            try {
                currentPlayer.stop();
                currentPlayer.release();
            } catch (Exception e) {}
            currentPlayer = null;
        }
        synchronized (queue) {
            for (Sentence s : queue) {
                if (s.wavFile != null && s.wavFile.exists()) {
                    s.wavFile.delete();
                }
            }
            queue.clear();
        }
        postStats();
    }
}
