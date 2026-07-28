import process from 'node:process';
import { organizeFile, resolveFfprobe, scanMedia } from './core.mjs';

let controller = null;

function send(message) {
  process.parentPort?.postMessage(message);
}

async function runJob(message) {
  controller = new AbortController();
  const startedAt = performance.now();
  try {
    send({ type: 'phase', phase: 'scanning' });
    const scan = await scanMedia(message.entries, {
      includeHidden: message.options.includeHidden,
      extensions: message.options.extensions,
      signal: controller.signal
    });
    for (const warning of scan.warnings) send({ type: 'warning', message: warning });
    if (scan.cancelled) throw new Error('cancelled');
    const ffprobe = await resolveFfprobe(message.options.ffprobePath);
    send({ type: 'scan-complete', totalFiles: scan.files.length, ffprobeAvailable: Boolean(ffprobe) });
    send({ type: 'phase', phase: 'organizing' });

    let completed = 0;
    let completedBytes = 0;
    let failed = 0;
    const totalBytes = (await Promise.all(scan.files.map(async (file) => {
      const { stat } = await import('node:fs/promises');
      return (await stat(file)).size;
    }))).reduce((sum, size) => sum + size, 0);

    for (const file of scan.files) {
      if (controller.signal.aborted) throw new Error('cancelled');
      send({ type: 'current-file', file });
      try {
        const beforeFileBytes = completedBytes;
        const result = await organizeFile(file, {
          destination: message.options.destination,
          layout: message.options.layout,
          duplicateMode: message.options.duplicateMode,
          transferMode: message.options.transferMode,
          dryRun: message.options.dryRun,
          ffprobe,
          signal: controller.signal,
          onProgress: (delta) => {
            completedBytes += delta;
            const elapsedSeconds = Math.max((performance.now() - startedAt) / 1000, 0.001);
            send({
              type: 'progress',
              completed,
              total: scan.files.length,
              completedBytes,
              totalBytes,
              bytesPerSecond: completedBytes / elapsedSeconds
            });
          }
        });
        if (completedBytes === beforeFileBytes) completedBytes += result.bytes;
        completed += 1;
        send({ type: 'result', result });
      } catch (error) {
        failed += 1;
        send({ type: 'file-error', file, message: error.message });
      }
      send({
        type: 'progress',
        completed,
        total: scan.files.length,
        completedBytes,
        totalBytes,
        bytesPerSecond: completedBytes / Math.max((performance.now() - startedAt) / 1000, 0.001)
      });
    }
    send({ type: 'done', completed, failed, total: scan.files.length });
  } catch (error) {
    send({ type: error.message === 'cancelled' ? 'cancelled' : 'fatal-error', message: error.message });
  } finally {
    controller = null;
  }
}

process.parentPort?.on('message', (event) => {
  const message = event.data;
  if (message?.type === 'start' && !controller) void runJob(message);
  if (message?.type === 'cancel') controller?.abort();
});
