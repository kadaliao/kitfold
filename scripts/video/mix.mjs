// Put sound on the rendered launch video: the narration clips at their places (from voice.mjs's
// timeline.json) and music underneath that dips while the narrator speaks.
//
//   node scripts/video/mix.mjs --video silent.mp4 --timeline timeline.json [--music m.mp3] --out final.mp4
//
// Narration is brought to -16 LUFS and the music bed to -22 LUFS; without narration the music
// alone is brought to -16 LUFS.
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const opt = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) opt[argv[i].replace(/^--/, '')] = argv[i + 1];
if (!opt.video || !opt.timeline || !opt.out) {
  console.error('usage: mix.mjs --video <silent.mp4> --timeline <timeline.json> [--music <file>] --out <file>');
  process.exit(2);
}
const tl = JSON.parse(readFileSync(opt.timeline, 'utf8'));
const D = tl.duration, clips = tl.clips ?? [];

function ff(args) {
  const r = spawnSync('ffmpeg', ['-y', '-hide_banner', '-nostats', ...args], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`ffmpeg failed:\n${r.stderr.slice(-2000)}`);
  return r.stderr;
}
/** Integrated loudness in LUFS. */
function lufs(file) {
  const m = [...ff(['-i', file, '-af', 'ebur128=framelog=quiet', '-f', 'null', '-']).matchAll(/I:\s+(-?[\d.]+) LUFS/g)].at(-1);
  if (!m) throw new Error(`could not measure ${file}`);
  return +m[1];
}

if (!clips.length && !opt.music) { copyFileSync(opt.video, opt.out); process.exit(0); }
const work = mkdtempSync(join(tmpdir(), 'kitfold-mix-'));
try {
  const inputs = [], parts = [];
  if (clips.length) {
    // One narration track as long as the video, each clip at its start time.
    const vo = join(work, 'voice.wav');
    const delays = clips.map((c, i) => `[${i}:a]aresample=48000,adelay=delays=${Math.round(c.start * 1000)}:all=1[c${i}]`);
    ff([...clips.flatMap(c => ['-i', c.file]), '-filter_complex',
      `${delays.join(';')};${clips.map((_, i) => `[c${i}]`).join('')}amix=inputs=${clips.length}:normalize=0,apad,atrim=0:${D}[v]`,
      '-map', '[v]', '-ac', '2', '-ar', '48000', vo]);   // stereo before measuring: L+R count twice in LUFS
    inputs.push(vo);
    parts.push({ kind: 'voice', gain: -16 - lufs(vo) });
  }
  if (opt.music) {
    const m = join(work, 'music.wav');
    ff(['-stream_loop', '-1', '-i', opt.music, '-af', `atrim=0:${D},asetpts=PTS-STARTPTS`, '-ac', '2', '-ar', '48000', m]);
    inputs.push(m);
    parts.push({ kind: 'music', gain: (clips.length ? -22 : -16) - lufs(m) });
  }

  const g = k => parts.find(p => p.kind === k).gain.toFixed(2);
  const fades = `afade=t=in:d=0.6,afade=t=out:st=${(D - 3).toFixed(3)}:d=3`;
  let graph;
  if (clips.length && opt.music) {
    graph = `[1:a]volume=${g('voice')}dB,asplit=2[key][vo];` +
            `[2:a]volume=${g('music')}dB,${fades}[bed];` +
            `[bed][key]sidechaincompress=threshold=0.05:ratio=3:attack=30:release=500[duck];` +
            `[duck][vo]amix=inputs=2:normalize=0,alimiter=limit=0.89:level=disabled[a]`;
  } else if (clips.length) {
    graph = `[1:a]volume=${g('voice')}dB,alimiter=limit=0.89:level=disabled[a]`;
  } else {
    graph = `[1:a]volume=${g('music')}dB,${fades},alimiter=limit=0.89:level=disabled[a]`;
  }
  ff(['-i', opt.video, ...inputs.flatMap(f => ['-i', f]), '-filter_complex', graph, '-map', '0:v', '-map', '[a]',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', String(D), '-movflags', '+faststart', opt.out]);
  console.log(`  ${opt.out}: ${lufs(opt.out).toFixed(1)} LUFS`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
