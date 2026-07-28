const extensions = ['osv','insv','mp4','mov','m4v','avi','mkv','webm','jpg','jpeg','jfif','png','heic','heif','tif','tiff','bmp','webp','dng','arw','cr2','cr3','nef','nrw','orf','raf','rw2','pef','srw','3fr','erf','mrw','raw','rwl','x3f'];
const sourcePaths = new Set();
let running = false;
const $ = (selector) => document.querySelector(selector);

function formatBytes(value) {
  if (!Number.isFinite(value) || value <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
  return `${(value / 1024 ** index).toFixed(index > 1 ? 1 : 0)} ${units[index]}`;
}

function appendLog(message) {
  const log = $('#log');
  log.textContent += `${new Date().toLocaleTimeString()}  ${message}\n`;
  log.scrollTop = log.scrollHeight;
}

function renderSources() {
  $('#sourceCount').textContent = `${sourcePaths.size}개 경로`;
  const list = $('#sourceList');
  list.replaceChildren(...Array.from(sourcePaths, (source) => {
    const item = document.createElement('li');
    const code = document.createElement('code');
    code.textContent = source;
    const remove = document.createElement('button');
    remove.textContent = '삭제';
    remove.addEventListener('click', () => { sourcePaths.delete(source); renderSources(); });
    item.append(code, remove);
    return item;
  }));
}

function selectedExtensions() {
  return Array.from(document.querySelectorAll('#extensions input:checked'), (input) => input.value);
}

function settingsFromForm() {
  return {
    destination: $('#destination').value,
    layout: $('#layout').value,
    duplicateMode: $('#duplicateMode').value,
    transferMode: $('#transferMode').value,
    dryRun: $('#dryRun').checked,
    includeHidden: $('#includeHidden').checked,
    extensions: selectedExtensions(),
    ffprobePath: $('#ffprobePath').value.trim()
  };
}

function applySettings(settings) {
  for (const key of ['destination', 'layout', 'duplicateMode', 'transferMode', 'ffprobePath']) $(`#${key}`).value = settings[key] ?? '';
  for (const key of ['dryRun', 'includeHidden']) $(`#${key}`).checked = Boolean(settings[key]);
  const selected = new Set(settings.extensions ?? extensions);
  for (const input of document.querySelectorAll('#extensions input')) input.checked = selected.has(input.value);
  updateSafetyNote();
}

function updateSafetyNote() {
  $('#safetyNote').classList.toggle('hidden', $('#duplicateMode').value !== 'fileSizeOnly');
}

function setRunning(value) {
  running = value;
  $('#startJob').disabled = value;
  $('#cancelJob').disabled = !value;
  $('#statusBadge').textContent = value ? '작업 중' : '대기';
}

for (const extension of extensions) {
  const label = document.createElement('label');
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.value = extension;
  label.append(input, `.${extension}`);
  $('#extensions').append(label);
}

$('#addFiles').addEventListener('click', async () => { for (const value of await window.osvcopy.chooseFiles()) sourcePaths.add(value); renderSources(); });
$('#addFolders').addEventListener('click', async () => { for (const value of await window.osvcopy.chooseFolders()) sourcePaths.add(value); renderSources(); });
$('#clearSources').addEventListener('click', () => { sourcePaths.clear(); renderSources(); });
$('#chooseDestination').addEventListener('click', async () => { const value = await window.osvcopy.chooseDestination(); if (value) $('#destination').value = value; });
$('#duplicateMode').addEventListener('change', updateSafetyNote);

const dropZone = $('#dropZone');
for (const eventName of ['dragenter', 'dragover']) dropZone.addEventListener(eventName, (event) => { event.preventDefault(); dropZone.classList.add('dragging'); });
for (const eventName of ['dragleave', 'drop']) dropZone.addEventListener(eventName, (event) => { event.preventDefault(); dropZone.classList.remove('dragging'); });
dropZone.addEventListener('drop', (event) => { for (const value of window.osvcopy.pathsForFiles(event.dataTransfer.files)) sourcePaths.add(value); renderSources(); });

$('#startJob').addEventListener('click', async () => {
  const settings = settingsFromForm();
  if (sourcePaths.size === 0) return appendLog('소스 파일이나 폴더가 없습니다.');
  if (!settings.destination) return appendLog('대상 라이브러리를 선택하세요.');
  if (settings.extensions.length === 0) return appendLog('확장자를 하나 이상 선택하세요.');
  await window.osvcopy.saveSettings(settings);
  $('#log').textContent = '';
  $('#progress').value = 0;
  setRunning(true);
  try {
    await window.osvcopy.startJob({ entries: Array.from(sourcePaths), options: settings });
  } catch (error) {
    appendLog(error.message);
    setRunning(false);
  }
});
$('#cancelJob').addEventListener('click', () => window.osvcopy.cancelJob());

window.osvcopy.onJobEvent((event) => {
  if (event.type === 'phase') appendLog(event.phase === 'scanning' ? '파일을 스캔합니다.' : '정리를 시작합니다.');
  if (event.type === 'scan-complete') appendLog(`${event.totalFiles}개 파일 발견 · ffprobe ${event.ffprobeAvailable ? '사용' : '없음'}`);
  if (event.type === 'warning') appendLog(`경고: ${event.message}`);
  if (event.type === 'current-file') $('#currentFile').textContent = event.file;
  if (event.type === 'result') appendLog(`${event.result.status}: ${event.result.source} → ${event.result.destination}`);
  if (event.type === 'file-error') appendLog(`오류: ${event.file} · ${event.message}`);
  if (event.type === 'progress') {
    const fraction = event.totalBytes > 0 ? event.completedBytes / event.totalBytes : event.completed / Math.max(event.total, 1);
    $('#progress').value = Math.min(Math.max(fraction, 0), 1);
    $('#progressText').textContent = `${event.completed}/${event.total} · ${formatBytes(event.completedBytes)} / ${formatBytes(event.totalBytes)} · ${formatBytes(event.bytesPerSecond)}/s`;
  }
  if (event.type === 'done') { appendLog(`완료: 성공 ${event.completed}, 실패 ${event.failed}`); setRunning(false); }
  if (event.type === 'cancelled') { appendLog('취소했습니다.'); setRunning(false); }
  if (event.type === 'fatal-error') { appendLog(`작업 중단: ${event.message}`); setRunning(false); }
});

applySettings(await window.osvcopy.loadSettings());
renderSources();
