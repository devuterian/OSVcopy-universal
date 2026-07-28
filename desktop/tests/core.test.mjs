import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  copyFileAtomic,
  dateFromZonedMetadata,
  datePartsFromMetadata,
  destinationDirectory,
  filesAreSame,
  normalizeComparablePath,
  normalizeExtension,
  organizeFile,
  parseCamFilename,
  scanMedia,
  uniqueDestination
} from '../src/core.mjs';

async function tempDirectory() { return mkdtemp(path.join(os.tmpdir(), 'osvcopy-')); }

test('normalizes extensions', () => {
  assert.equal(normalizeExtension('.MP4'), 'mp4');
  assert.equal(normalizeExtension('..OSV'), 'osv');
});

test('parses CAM filename date', () => {
  assert.equal(parseCamFilename('/tmp/CAM_20260728125959_123.OSV'), '2026-07-28');
  assert.equal(parseCamFilename('/tmp/CAM_20261301125959_123.OSV'), null);
});

test('metadata preserves the encoded capture day', () => {
  assert.equal(datePartsFromMetadata('2026:07:28 00:15:00'), '2026-07-28');
  assert.equal(dateFromZonedMetadata('2026-07-28T23:45:00-05:00'), '2026-07-28');
});

test('builds both destination layouts', () => {
  assert.equal(destinationDirectory('/library', '2026-07-28', 'flatDate'), path.join('/library', '2026-07-28'));
  assert.equal(destinationDirectory('/library', '2026-07-28', 'yearThenDate'), path.join('/library', '2026', '2026-07-28'));
});

test('normalizes Windows paths case-insensitively', () => {
  assert.equal(normalizeComparablePath('C:\\Media\\A.OSV', 'win32'), normalizeComparablePath('c:\\media\\a.osv', 'win32'));
});

test('finds a unique destination', async () => {
  const root = await tempDirectory();
  const preferred = path.join(root, 'clip.mp4');
  await writeFile(preferred, 'a');
  assert.equal(await uniqueDestination(preferred), path.join(root, 'clip_1.mp4'));
});

test('compares content by MD5', async () => {
  const root = await tempDirectory();
  const a = path.join(root, 'a.mp4');
  const b = path.join(root, 'b.mp4');
  await writeFile(a, 'same');
  await writeFile(b, 'same');
  assert.equal(await filesAreSame(a, b, 'md5'), true);
  await writeFile(b, 'diff');
  assert.equal(await filesAreSame(a, b, 'md5'), false);
});

test('scans recursively and excludes hidden files', async () => {
  const root = await tempDirectory();
  await mkdir(path.join(root, 'nested'));
  await mkdir(path.join(root, '.hidden'));
  await writeFile(path.join(root, 'nested', 'A.MP4'), 'x');
  await writeFile(path.join(root, '.hidden', 'B.MP4'), 'x');
  const result = await scanMedia([root], { includeHidden: false, extensions: ['mp4'] });
  assert.deepEqual(result.files, [path.join(root, 'nested', 'A.MP4')]);
});

test('atomic copy completes and leaves exact content', async () => {
  const root = await tempDirectory();
  const source = path.join(root, 'source.mp4');
  const destination = path.join(root, 'out', 'destination.mp4');
  await writeFile(source, '123456789');
  await copyFileAtomic(source, destination);
  assert.equal(await readFile(destination, 'utf8'), '123456789');
});

test('size-only move verifies MD5 before deleting source', async () => {
  const root = await tempDirectory();
  const source = path.join(root, 'CAM_20260728120000_clip.mp4');
  const destinationRoot = path.join(root, 'library');
  const destinationDir = destinationDirectory(destinationRoot, '2026-07-28', 'flatDate');
  await mkdir(destinationDir, { recursive: true });
  await writeFile(source, 'AAAA');
  await writeFile(path.join(destinationDir, path.basename(source)), 'BBBB');
  const result = await organizeFile(source, {
    destination: destinationRoot,
    layout: 'flatDate',
    duplicateMode: 'fileSizeOnly',
    transferMode: 'move',
    dryRun: false,
    ffprobe: null
  });
  assert.equal(result.status, 'completed');
  assert.equal((await stat(source).catch(() => null)), null);
  assert.equal(await readFile(result.destination, 'utf8'), 'AAAA');
  assert.match(result.destination, /_1\.mp4$/);
});


test('deduplicates identical source paths', async () => {
  const root = await tempDirectory();
  const file = path.join(root, 'A.MP4');
  await writeFile(file, 'x');
  const result = await scanMedia([file, file], { extensions: ['mp4'] });
  assert.deepEqual(result.files, [file]);
});

test('an already-cancelled copy leaves no destination', async () => {
  const root = await tempDirectory();
  const source = path.join(root, 'source.mp4');
  const destination = path.join(root, 'out', 'destination.mp4');
  await writeFile(source, 'payload');
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(copyFileAtomic(source, destination, { signal: controller.signal }));
  assert.equal(await stat(destination).catch(() => null), null);
});
