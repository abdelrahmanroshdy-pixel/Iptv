import sys
from faster_whisper import WhisperModel
m=WhisperModel(sys.argv[1],device='cpu',compute_type='int8',download_root='models')
import librosa; y,_=librosa.load('my/rec16.wav',sr=16000); segs,info=m.transcribe(y,language='ar',word_timestamps=True,beam_size=5,vad_filter=False)
for s in segs:
    print(f"[{s.start:6.2f}-{s.end:6.2f}] {s.text}")
    print('   ',' '.join(f"{w.word.strip()}({w.start:.2f})" for w in s.words))
