import numpy as np, wave
SR=48000; DUR=30.0
rng=np.random.default_rng(7)
out=np.zeros(int(SR*DUR))
def add(sig,t,g=1.0):
    i=int(t*SR); n=min(len(sig),len(out)-i); out[i:i+n]+=sig[:n]*g
def env(n,a,d):
    t=np.arange(n)/SR; return np.minimum(1,t/max(a,1e-4))*np.exp(-t/d)
def lp(x,a):  # one-pole lowpass, a in (0,1)
    y=np.zeros_like(x); s=0
    for i,v in enumerate(x): s+=a*(v-s); y[i]=s
    return y
def whoosh(d=0.5,lo=0.04,hi=0.35,g=1.0):
    n=int(d*SR); x=rng.standard_normal(n); t=np.linspace(0,1,n)
    cut=lo+(hi-lo)*np.sin(np.pi*t)**2
    y=np.zeros(n); s=0;s2=0
    for i in range(n): s+=cut[i]*(x[i]-s); s2+=cut[i]*(s-s2); y[i]=s2
    y-=lp(y,0.01)
    e=np.sin(np.pi*t)**1.5
    return y*e/ (np.abs(y*e).max()+1e-9)*0.6*g
def pop(f0=900,f1=380,d=0.09,g=1.0):
    n=int(d*SR); t=np.arange(n)/SR; f=f1+(f0-f1)*np.exp(-t/0.015)
    ph=2*np.pi*np.cumsum(f)/SR; return np.sin(ph)*env(n,0.002,d/4)*0.7*g
def click(g=1.0,f=3200):
    n=int(0.035*SR); t=np.arange(n)/SR
    nz=rng.standard_normal(n); nz=nz-lp(nz,0.25)
    body=np.sin(2*np.pi*f*t)*0.4+np.sin(2*np.pi*f*0.37*t)*0.3
    return (nz*0.5+body)*env(n,0.0005,0.006)*0.5*g
def thump():
    n=int(0.25*SR); t=np.arange(n)/SR
    s=np.sin(2*np.pi*(70+90*np.exp(-t/0.03))*t)*env(n,0.001,0.07)
    nz=lp(rng.standard_normal(n),0.08)*env(n,0.001,0.03)*2
    return (s+nz)*0.8
def tick():
    n=int(0.06*SR); t=np.arange(n)/SR
    return (np.sin(2*np.pi*2600*t)*0.6+np.sin(2*np.pi*5200*t)*0.25)*env(n,0.0005,0.008)*0.8
# timeline (matches index.html T)
add(pop(1100,600,0.08,0.6),0.02)
add(whoosh(0.55),5.40)
add(pop(800,300,0.12),5.90)
add(whoosh(0.5,0.05,0.4,0.9),6.62)
add(whoosh(0.5,0.03,0.25,0.7),7.98)
add(thump(),8.75)
for k,tt in enumerate([8.88,8.95,9.03,9.12,9.2,9.31]): add(pop(1500+180*k,900,0.06,0.35),tt)
add(whoosh(0.45,0.04,0.35,0.8),10.55)
Q3=['إ','ز','ا','ي',' ','أ','ج','هّ','ز',' ','ل','ل','ع','م','ر','ة']
a,b=11.0,13.55; n=len(Q3)
for k in range(1,n+1): add(click(0.8+0.4*rng.random(),2800+800*rng.random()),a+(k-0.5)/n*(b-a))
add(click(1.3,1800),13.95)
for tt in [15.22,16.37,17.74]: add(pop(950,420,0.1,0.8),tt)
add(whoosh(0.9,0.02,0.15,0.8),19.30)
for tt in [20.93,22.55]: add(pop(1300,700,0.08,0.8),tt)
add(tick(),27.65)
x=out/ (np.abs(out).max()+1e-9)*0.9
with wave.open('audio/sfx.wav','wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR);w.writeframes((x*32767).astype('<i2').tobytes())
print(len(Q3))
