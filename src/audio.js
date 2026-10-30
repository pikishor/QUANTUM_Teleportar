// Tiny procedural synth so the game ships without audio assets.
let ac = null, master = null, noiseBuf = null;

export function initAudio() {
  if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
  try {
    ac = new (window.AudioContext || window.webkitAudioContext)();
    master = ac.createGain(); master.gain.value = 0.35; master.connect(ac.destination);
    noiseBuf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  } catch (e) { ac = null; }
}

function tone(type, f0, f1, dur, vol = 0.3) {
  if (!ac) return;
  const t = ac.currentTime, o = ac.createOscillator(), g = ac.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.02);
}

function noise(dur, vol = 0.3, lp = 4000) {
  if (!ac) return;
  const t = ac.currentTime, s = ac.createBufferSource(), g = ac.createGain(), f = ac.createBiquadFilter();
  s.buffer = noiseBuf;
  f.type = 'lowpass';
  f.frequency.setValueAtTime(lp, t);
  f.frequency.exponentialRampToValueAtTime(200, t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  s.connect(f); f.connect(g); g.connect(master); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
}

export const sfx = {
  shot: () => { noise(0.1, 0.3, 5000); tone('square', 220, 60, 0.09, 0.15); },
  enemyShot: () => tone('sawtooth', 700, 200, 0.16, 0.08),
  hit: () => tone('square', 900, 500, 0.05, 0.1),
  hurt: () => { noise(0.2, 0.3, 1200); tone('sine', 120, 50, 0.25, 0.3); },
  boom: () => { noise(0.7, 0.6, 1800); tone('sine', 90, 30, 0.6, 0.5); },
  blink: () => { tone('sine', 300, 1800, 0.25, 0.25); tone('triangle', 1800, 300, 0.25, 0.15); },
  link: () => { tone('sine', 520, 780, 0.2, 0.2); tone('sine', 780, 520, 0.2, 0.15); },
  superpos: () => { tone('sine', 440, 440, 0.4, 0.15); tone('sine', 466, 466, 0.4, 0.15); },
  pickup: () => tone('triangle', 660, 990, 0.12, 0.2),
  reload: () => noise(0.06, 0.2, 3000),
  core: () => { tone('triangle', 523, 1046, 0.4, 0.25); tone('sine', 784, 1568, 0.4, 0.15); },
};
