// Render scene.html frame by frame in headless Chrome and encode it with ffmpeg.
// No npm packages: Node's built-in WebSocket speaks the DevTools protocol directly.
//
//   node scripts/video/render.mjs --assets <dir> --out video.mp4 [--fps 60] [--duration 55]
//   node scripts/video/render.mjs --assets <dir> --still 29.5 --out frame.png   (one frame, for checking)
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const opt = { fps: 60, duration: 55, chrome: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) opt[argv[i].replace(/^--/, '')] = argv[i + 1];
if (!opt.assets || !opt.out) { console.error('usage: render.mjs --assets <dir> --out <file> [--fps 60] [--duration 55] [--still <t>]'); process.exit(2); }
const fps = +opt.fps, frames = Math.round(+opt.duration * fps);
const page = `file://${join(dirname(fileURLToPath(import.meta.url)), 'scene.html')}?assets=${encodeURIComponent(resolve(opt.assets))}`;

const profile = mkdtempSync(join(tmpdir(), 'kitfold-video-'));
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn(opt.chrome, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--hide-scrollbars',
  '--allow-file-access-from-files', '--force-color-profile=srgb', '--mute-audio', '--no-first-run', 'about:blank',
], { stdio: 'ignore' });
const cleanup = () => {
  chrome.kill();
  try { rmSync(profile, { recursive: true, force: true, maxRetries: 5 }); } catch { /* Chrome may still be flushing it */ }
};
process.on('exit', cleanup);

async function target() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const p = list.find(x => x.type === 'page');
      if (p) return p.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Chrome did not start');
}

const ws = new WebSocket(await target());
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let seq = 0;
const pending = new Map();
ws.onmessage = e => {
  const m = JSON.parse(e.data);
  if (!m.id || !pending.has(m.id)) return;
  const { res, rej } = pending.get(m.id);
  pending.delete(m.id);
  m.error ? rej(new Error(m.error.message)) : res(m.result);
};
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = ++seq;
  pending.set(id, { res, rej });
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expr => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? 'script error');
  return r.result.value;
};

await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
await send('Page.enable');
await send('Page.navigate', { url: page });
for (let i = 0; i < 100 && !(await evaluate('typeof window.ready !== "undefined"').catch(() => false)); i++) {
  await new Promise(r => setTimeout(r, 100));
}
await evaluate('window.ready');

if (opt.still !== undefined) {
  await evaluate(`seek(${+opt.still})`);
  const { data } = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(opt.out, Buffer.from(data, 'base64'));
  process.exit(0);
}

const ffmpeg = spawn('ffmpeg', [
  '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-r', String(fps), '-movflags', '+faststart', opt.out,
], { stdio: ['pipe', 'inherit', 'inherit'] });

const started = Date.now();
for (let f = 0; f < frames; f++) {
  await evaluate(`seek(${f / fps})`);
  const { data } = await send('Page.captureScreenshot', { format: 'jpeg', quality: 95 });
  if (!ffmpeg.stdin.write(Buffer.from(data, 'base64'))) await new Promise(r => ffmpeg.stdin.once('drain', r));
  if (f % fps === 0) process.stderr.write(`\r  ${(f / fps).toFixed(0)}s / ${opt.duration}s  (${((Date.now() - started) / 1000).toFixed(0)}s elapsed)`);
}
ffmpeg.stdin.end();
await new Promise((res, rej) => ffmpeg.on('close', code => code === 0 ? res() : rej(new Error(`ffmpeg exited ${code}`))));
process.stderr.write(`\n  wrote ${opt.out}\n`);
process.exit(0);
