// Narration for the launch video: speak each scene's line with Gemini TTS, then stretch the
// timeline so every scene is long enough for its line.
//
//   node scripts/video/voice.mjs --lang zh --out <dir> [--cache build/video/voice] [--silent]
//
// Writes into <dir>:
//   timeline.js    window.TIMELINE for scene.html: how scene time maps to video time, and subtitles
//   timeline.json  the same, plus where each clip goes (read by mix.mjs)
//   subs.srt       subtitles of the narration
// With --silent there is no narration: the timeline is the scene's own and has no subtitles.
//
// Clips are cached by model, voice, style and text, so re-runs only pay for lines that changed.
// Credentials: GEMINI_API_KEY (Google AI Studio), or AIHUBMIX_API_KEY for AIHubMix's Gemini-native
// proxy (set AIHUBMIX_IP to pin its address if your DNS resolves it badly).
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { request } from 'node:https';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const opt = { lang: 'en', cache: 'build/video/voice' };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const k = argv[i].replace(/^--/, '');
  if (k === 'silent') opt.silent = true; else opt[k] = argv[++i];
}
if (!opt.out) { console.error('usage: voice.mjs --lang en|zh --out <dir> [--cache <dir>] [--silent]'); process.exit(2); }

const N = JSON.parse(readFileSync(join(here, 'narration.json'), 'utf8'));
const scenes = N.scenes;
const lines = scenes.map(s => s[opt.lang]);
if (lines.some(l => !l)) { console.error(`narration.json has no "${opt.lang}" line for every scene`); process.exit(2); }

// ---------- synthesis ----------
function endpoint() {
  if (process.env.GEMINI_API_KEY) {
    return { host: 'generativelanguage.googleapis.com', path: '/v1beta/interactions', key: process.env.GEMINI_API_KEY };
  }
  if (process.env.AIHUBMIX_API_KEY) {
    return { host: 'aihubmix.com', path: '/gemini/v1beta/interactions', key: process.env.AIHUBMIX_API_KEY, ip: process.env.AIHUBMIX_IP };
  }
  throw new Error('Narration needs GEMINI_API_KEY or AIHUBMIX_API_KEY (or run with --silent)');
}

function post(ep, body) {
  const data = Buffer.from(JSON.stringify(body));
  const lookup = ep.ip ? (_h, o, cb) => (o?.all ? cb(null, [{ address: ep.ip, family: 4 }]) : cb(null, ep.ip, 4)) : undefined;
  return new Promise((res, rej) => {
    const req = request({ host: ep.host, servername: ep.host, path: ep.path, method: 'POST', lookup, timeout: 120_000,
      headers: { 'content-type': 'application/json', 'content-length': data.length, 'x-goog-api-key': ep.key } }, r => {
      const chunks = [];
      r.on('data', c => chunks.push(c));
      r.on('end', () => res({ status: r.statusCode, text: Buffer.concat(chunks).toString('utf8') }));
      r.on('error', rej);
    });
    req.on('timeout', () => req.destroy(new Error('timed out')));
    req.on('error', rej);
    req.end(data);
  });
}

async function speak(text, style) {
  const ep = endpoint();
  const body = {
    model: N.model,
    input: [{ type: 'user_input', content: [{ type: 'text', text, annotations: [{ type: 'speech_metadata', style }] }] }],
    response_format: { type: 'audio' },
    generation_config: { speech_config: [{ voice: N.voice }] },
    store: false,
  };
  for (let attempt = 1; ; attempt++) {
    let r;
    try { r = await post(ep, body); } catch (e) { r = { status: 0, text: e.message }; }
    const retry = r.status === 0 || r.status === 429 || r.status >= 500;
    if (r.status === 200) {
      const j = JSON.parse(r.text);
      const audio = (j.steps ?? []).filter(s => s.type === 'model_output').flatMap(s => s.content ?? [])
        .filter(c => c.type === 'audio' && c.data).at(-1);
      const wav = audio && Buffer.from(audio.data, 'base64');
      if (wav?.subarray(0, 4).toString() === 'RIFF') return wav;
      if (attempt >= 3) throw new Error('TTS returned no WAV audio');
    } else if (!retry || attempt >= 3) {
      // Never echo the key: error bodies can quote request headers.
      throw new Error(`TTS HTTP ${r.status}: ${r.text.split(ep.key).join('[key]').slice(0, 400)}`);
    }
    await new Promise(res => setTimeout(res, 1500 * attempt));
  }
}

const ff = args => {
  const r = spawnSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...args], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`ffmpeg failed: ${r.stderr}`);
};
const duration = file => +spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file],
  { encoding: 'utf8' }).stdout.trim();

/** The clip for one line: cached raw TTS output, trimmed of leading and trailing silence. */
async function clip(text) {
  const style = N.style[opt.lang] ?? '';
  const id = createHash('sha256').update(JSON.stringify([N.model, N.voice, style, text])).digest('hex').slice(0, 16);
  const dir = resolve(opt.cache, opt.lang);
  const raw = join(dir, `${id}.raw.wav`), trimmed = join(dir, `${id}.wav`);
  mkdirSync(dir, { recursive: true });
  if (!existsSync(raw)) {
    process.stderr.write(`  speaking: ${text}\n`);
    writeFileSync(raw + '.part', await speak(text, style));
    renameSync(raw + '.part', raw);
  }
  if (!existsSync(trimmed)) {
    const edge = 'silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.06';
    ff(['-i', raw, '-af', `${edge},areverse,${edge},areverse,aresample=48000`, '-ac', '1', trimmed]);
  }
  return { file: trimmed, dur: duration(trimmed) };
}

// ---------- timeline ----------
const LEAD = 0.35, TAIL = 0.5, END_TAIL = 1.6;   // seconds around each line
const from = [scenes[0].at[0], ...scenes.map(s => s.at[1])];
const to = [from[0]];
const clips = [];
for (let i = 0; i < scenes.length; i++) {
  const own = from[i + 1] - from[i];
  let len = own;
  if (!opt.silent) {
    let said = lines[i].replaceAll('|', '');
    for (const [word, sound] of Object.entries(N.say?.[opt.lang] ?? {})) said = said.replaceAll(word, sound);
    const c = await clip(said);
    const lead = i === 0 ? 0.45 : LEAD;
    len = Math.max(own, lead + c.dur + (i === scenes.length - 1 ? END_TAIL : TAIL));
    clips.push({ ...c, start: +(to[i] + lead).toFixed(3), line: lines[i], scene: scenes[i].id });
    const stretch = len / own;
    if (stretch > 1.35) console.warn(`  note: "${scenes[i].id}" runs ${stretch.toFixed(2)}× its own length; consider a shorter line`);
  }
  to.push(+(to[i] + len).toFixed(3));
}

// ---------- subtitles: the pieces between `|` marks, timed by how long each takes to say ----------
const cjk = /[\u3000-\u9fff\uff00-\uffef]/;
const spoken = s => [...s].reduce((n, ch) => n + (/[，。：；、！？,.:;!?—]/.test(ch) ? 1.2 : cjk.test(ch) ? 1 : /\s/.test(ch) ? .15 : .33), 0);
const clean = s => s.trim().replace(/[，。：；、,.:;]$/, '').replace(/[，。；]/g, ' ').trim();
const subs = [];
for (const c of clips) {
  const ps = c.line.split('|'), total = ps.reduce((n, p) => n + spoken(p), 0);
  let t = c.start;
  for (const p of ps) {
    const d = c.dur * spoken(p) / total;
    subs.push({ a: +t.toFixed(3), b: +(t + d).toFixed(3), text: clean(p) });
    t += d;
  }
}
// Close small gaps between subtitles so the text doesn't blink.
for (let i = 1; i < subs.length; i++) if (subs[i].a - subs[i - 1].b < 0.25) subs[i - 1].b = subs[i].a;

const srtTime = s => {
  const ms = Math.round(s * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, sec = Math.floor(ms / 1000) % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')},${String(ms % 1000).padStart(3, '0')}`;
};
const timeline = { lang: opt.lang, duration: to.at(-1), map: { from, to }, subs, clips };
mkdirSync(opt.out, { recursive: true });
writeFileSync(join(opt.out, 'timeline.json'), JSON.stringify(timeline, null, 2));
writeFileSync(join(opt.out, 'timeline.js'), `window.TIMELINE = ${JSON.stringify({ lang: opt.lang, map: { from, to }, subs })};\n`);
writeFileSync(join(opt.out, 'subs.srt'), subs.map((s, i) => `${i + 1}\n${srtTime(s.a)} --> ${srtTime(s.b)}\n${s.text}\n`).join('\n'));
console.log(timeline.duration.toFixed(2));
