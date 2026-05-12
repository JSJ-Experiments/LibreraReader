package com.foobnix.tts;

public class TtsPreloadStats {
    public int pending;
    public int synthesized;
    public int playing;

    public TtsPreloadStats(int pending, int synthesized, int playing) {
        this.pending = pending;
        this.synthesized = synthesized;
        this.playing = playing;
    }
}
