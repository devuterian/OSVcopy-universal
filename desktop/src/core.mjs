import { createHash, randomUUID } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { access, mkdir, open, opendir, rename, rm, stat, unlink } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';

export const MEDIA_EXTENSIONS = Object.freeze([
  'osv', 'insv', 'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm',
  'jpg', 'jpeg', 'jfif', 'png', 'heic', 'heif', 'tif', 'tiff', 'bmp', 'webp',
  'dng', 'arw', 'cr2', 'cr3', 'nef', 'nrw', 'orf', 'raf', 'rw2', 'pef', 'srw',
  '3fr', 'erf', 'mrw', 'raw', 'rwl', 'x3f'
]);

const EXTENSION_SET = new Set(MEDIA_EXTENSIONS);
const CAM_PATTERN = /^CAM_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_/i;

export function normalizeExtension(value) {
  return String(value ?? '').trim().replace(/^\.+/, '').toLowerCase();
}

export function isMediaFile(filePath, selectedExtensions = MEDIA_EXTENSIONS) {
  const ext = normalizeExtension(path.extname(filePath));
  const selected = selectedExtensions instanceof Set
    ? selectedExtensions
    : new Set(selectedExtensions.map(normalizeExtension));
  return ext.length > 0 && EXTENSION_SET.has(ext) && selected.has(ext);
}

export function parseCamFilename(filePath) {
  const match = CAM_PATTERN.exec(path.basename(filePath));
  if (!match) return null;
  const [, year, month, day] = match;
  if (!isValidDateParts(year, month, day)) return null;
  return `${year}-${month}-${day}`;
}

function isValidDateParts(year, month, day) {
  const y = Number(year);
  const m = Number(month);
  const d = Number(day);
  const probe = new Date(Date.UTC(y, m - 1, d));
  return probe.getUTCFullYear() === y && probe.getUTCMonth() === m - 1 && probe.getUTCDate() === d;
}

export function datePartsFromMetadata(value) {
  if (typeof value !== 'string') return null;
  const match = value.trim().match(/^(\d{4})[:-](\d{2})[:-](\d{2})(?:[ T].*)?$/);
  if (!match) return null;
  const [, y, m, d] = match;
  return isValidDateParts(y, m, d) ? `${y}-${m}-${d}` : null;
}

export function dateFromZonedMetadata(value) {
  if (typeof value !== 'string') return null;
  const literalDay = datePartsFromMetadata(value);
  if (literalDay) return literalDay;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) return null;
  return formatLocalDay(parsed);
}

export function formatLocalDay(value) {
  const year = String(value.getFullYear()).padStart(4, '0');
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function destinationDirectory(base, day, layout) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new Error(`invalid day: ${day}`);
  if (layout === 'flatDate') return path.join(base, day);
  if (layout === 'yearThenDate') return path.join(base, day.slice(0, 4), day);
  throw new Error(`invalid layout: ${layout}`);
}

export function normalizeComparablePath(filePath, platform = process.platform) {
  const normalized = path.resolve(filePath).replace(/[\\/]+/g, path.sep);
  return platform === 'win32' ? normalized.toLowerCase() : normalized;
}

export async function pathExists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

export async function uniqueDestination(preferred) {
  if (!(await pathExists(preferred))) return preferred;
  const parsed = path.parse(preferred);
  for (let index = 1; index < 10_000; index += 1) {
    const candidate = path.join(parsed.dir, `${parsed.name}_${index}${parsed.ext}`);
    if (!(await pathExists(candidate))) return candidate;
  }
  throw new Error(`cannot find unique destination for ${preferred}`);
}

export async function md5File(filePath, signal) {
  const hash = createHash('md5');
  const input = createReadStream(filePath);
  const abort = () => input.destroy(new Error('cancelled'));
  signal?.addEventListener('abort', abort, { once: true });
  try {
    for await (const chunk of input) {
      if (signal?.aborted) throw new Error('cancelled');
      hash.update(chunk);
    }
    return hash.digest('hex');
  } finally {
    signal?.removeEventListener('abort', abort);
  }
}

export async function filesAreSame(source, destination, mode, signal) {
  const [sourceStat, destinationStat] = await Promise.all([stat(source), stat(destination)]);
  if (sourceStat.size !== destinationStat.size) return false;
  if (mode === 'fileSizeOnly') return true;
  const [sourceHash, destinationHash] = await Promise.all([
    md5File(source, signal),
    md5File(destination, signal)
  ]);
  return sourceHash === destinationHash;
}

export async function scanMedia(entries, options = {}) {
  const includeHidden = Boolean(options.includeHidden);
  const selected = new Set((options.extensions ?? MEDIA_EXTENSIONS).map(normalizeExtension));
  const signal = options.signal;
  const warnings = [];
  const files = [];
  const seenFiles = new Set();
  const seenDirectories = new Set();
  const stack = [...entries];

  while (stack.length > 0) {
    if (signal?.aborted) return { files, warnings, cancelled: true };
    const current = stack.pop();
    let info;
    try {
      info = await stat(current);
    } catch (error) {
      warnings.push(`${current}: ${error.message}`);
      continue;
    }

    const base = path.basename(current);
    if (!includeHidden && base.startsWith('.')) continue;

    if (info.isDirectory()) {
      let directoryKey;
      try {
        directoryKey = normalizeComparablePath(await import('node:fs/promises').then(({ realpath }) => realpath(current)));
      } catch {
        directoryKey = normalizeComparablePath(current);
      }
      if (seenDirectories.has(directoryKey)) continue;
      seenDirectories.add(directoryKey);
      try {
        const dir = await opendir(current);
        for await (const entry of dir) {
          if (!includeHidden && entry.name.startsWith('.')) continue;
          if (entry.isSymbolicLink()) continue;
          stack.push(path.join(current, entry.name));
        }
      } catch (error) {
        warnings.push(`${current}: ${error.message}`);
      }
      continue;
    }

    if (!info.isFile() || !isMediaFile(current, selected)) continue;
    const key = normalizeComparablePath(current);
    if (seenFiles.has(key)) continue;
    seenFiles.add(key);
    files.push(current);
  }

  files.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
  return { files, warnings, cancelled: false };
}

export async function findExecutable(nameOrPath) {
  if (!nameOrPath) return null;
  if (path.isAbsolute(nameOrPath) && await pathExists(nameOrPath)) return nameOrPath;
  const command = process.platform === 'win32' ? 'where' : 'which';
  return await new Promise((resolve) => {
    const child = spawn(command, [nameOrPath], { shell: false, windowsHide: true });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code === 0 ? output.trim().split(/\r?\n/)[0] : null));
  });
}

export async function resolveFfprobe(configuredPath) {
  if (configuredPath) {
    const configured = await findExecutable(configuredPath);
    if (configured) return configured;
  }
  return findExecutable(process.platform === 'win32' ? 'ffprobe.exe' : 'ffprobe');
}

export async function dateFromFfprobe(filePath, executable, signal) {
  if (!executable) return null;
  return await new Promise((resolve) => {
    const args = ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', filePath];
    const child = spawn(executable, args, { shell: false, windowsHide: true });
    let stdout = '';
    const abort = () => child.kill();
    signal?.addEventListener('abort', abort, { once: true });
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.on('error', () => resolve(null));
    child.on('close', (code) => {
      signal?.removeEventListener('abort', abort);
      if (code !== 0) return resolve(null);
      try {
        const json = JSON.parse(stdout);
        const candidates = [];
        if (json.format?.tags) candidates.push(...Object.values(json.format.tags));
        for (const stream of json.streams ?? []) {
          if (stream.tags) candidates.push(...Object.values(stream.tags));
        }
        for (const value of candidates) {
          if (typeof value !== 'string') continue;
          const day = /(?:Z|[+-]\d{2}:?\d{2})$/.test(value)
            ? dateFromZonedMetadata(value)
            : datePartsFromMetadata(value);
          if (day) return resolve(day);
        }
      } catch {
        // Ignore malformed metadata and continue to stat fallback.
      }
      resolve(null);
    });
  });
}

export async function resolveDate(filePath, options = {}) {
  const filenameDay = parseCamFilename(filePath);
  if (filenameDay) return { day: filenameDay, source: 'filename_cam' };
  const ffprobeDay = await dateFromFfprobe(filePath, options.ffprobe, options.signal);
  if (ffprobeDay) return { day: ffprobeDay, source: 'ffprobe' };
  const info = await stat(filePath);
  const value = Number.isFinite(info.birthtimeMs) && info.birthtimeMs > 0 ? info.birthtime : info.mtime;
  return { day: formatLocalDay(value), source: 'stat' };
}

export async function copyFileAtomic(source, destination, options = {}) {
  const signal = options.signal;
  if (signal?.aborted) throw new Error('cancelled');
  const sourceInfo = await stat(source);
  await mkdir(path.dirname(destination), { recursive: true });
  const temporary = path.join(path.dirname(destination), `.${path.basename(destination)}.osvcopy-part-${randomUUID()}`);
  let processed = 0;
  const input = createReadStream(source, { highWaterMark: 8 * 1024 * 1024 });
  const output = createWriteStream(temporary, { flags: 'wx' });
  const abort = () => {
    input.destroy(new Error('cancelled'));
    output.destroy(new Error('cancelled'));
  };
  signal?.addEventListener('abort', abort, { once: true });
  input.on('data', (chunk) => {
    processed += chunk.length;
    options.onProgress?.(chunk.length, processed, sourceInfo.size);
  });
  try {
    await pipeline(input, output);
    const temporaryInfo = await stat(temporary);
    if (temporaryInfo.size !== sourceInfo.size) throw new Error('copied file size mismatch');
    await rename(temporary, destination);
    return sourceInfo.size;
  } catch (error) {
    await rm(temporary, { force: true }).catch(() => {});
    throw error;
  } finally {
    signal?.removeEventListener('abort', abort);
  }
}

export async function moveFileSafe(source, destination, options = {}) {
  await mkdir(path.dirname(destination), { recursive: true });
  try {
    await rename(source, destination);
    return (await stat(destination)).size;
  } catch (error) {
    if (!['EXDEV', 'EPERM', 'EACCES'].includes(error.code)) throw error;
  }
  const bytes = await copyFileAtomic(source, destination, options);
  await unlink(source);
  return bytes;
}

export async function organizeFile(source, options) {
  const signal = options.signal;
  if (signal?.aborted) throw new Error('cancelled');
  const sourceInfo = await stat(source);
  const date = await resolveDate(source, { ffprobe: options.ffprobe, signal });
  const directory = destinationDirectory(options.destination, date.day, options.layout);
  const preferred = path.join(directory, path.basename(source));
  if (normalizeComparablePath(source) === normalizeComparablePath(preferred)) {
    throw new Error('source and destination are the same path');
  }

  if (await pathExists(preferred)) {
    const candidateDuplicate = await filesAreSame(source, preferred, options.duplicateMode, signal);
    if (candidateDuplicate) {
      if (options.transferMode === 'move' && options.duplicateMode === 'fileSizeOnly') {
        const reallySame = await filesAreSame(source, preferred, 'md5', signal);
        if (reallySame) {
          if (!options.dryRun) await unlink(source);
          return { status: 'skipped', source, destination: preferred, bytes: sourceInfo.size, date };
        }
      } else {
        if (options.transferMode === 'move' && !options.dryRun) await unlink(source);
        return { status: 'skipped', source, destination: preferred, bytes: sourceInfo.size, date };
      }
    }
  }

  const destination = await uniqueDestination(preferred);
  if (options.dryRun) {
    return { status: 'preview', source, destination, bytes: sourceInfo.size, date };
  }

  const transferOptions = { signal, onProgress: options.onProgress };
  const bytes = options.transferMode === 'move'
    ? await moveFileSafe(source, destination, transferOptions)
    : await copyFileAtomic(source, destination, transferOptions);
  return { status: 'completed', source, destination, bytes, date };
}
