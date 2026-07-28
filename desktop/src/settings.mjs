import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const DEFAULT_SETTINGS = Object.freeze({
  destination: '',
  layout: 'yearThenDate',
  duplicateMode: 'md5',
  transferMode: 'copy',
  dryRun: false,
  includeHidden: false,
  extensions: ['osv', 'insv', 'mp4', 'mov', 'jpg', 'jpeg', 'dng', 'arw'],
  ffprobePath: ''
});

export class SettingsStore {
  constructor(userDataPath) {
    this.directory = path.join(userDataPath, 'osvcopy-universal');
    this.file = path.join(this.directory, 'settings.json');
  }

  async load() {
    try {
      const value = JSON.parse(await readFile(this.file, 'utf8'));
      return { ...DEFAULT_SETTINGS, ...value };
    } catch {
      return { ...DEFAULT_SETTINGS };
    }
  }

  async save(value) {
    await mkdir(this.directory, { recursive: true });
    const temporary = `${this.file}.tmp`;
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    await rename(temporary, this.file);
  }
}
