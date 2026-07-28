# OSVcopy Universal Desktop

Electron 기반 Windows 데스크톱 앱입니다. 기존 SwiftUI macOS 앱과 같은 저장소에서 별도 패키지로 유지됩니다.

## 개발 실행

```bash
cd desktop
npm install
npm start
```

## 검사

```bash
npm test
npm run lint
```

## Windows 설치 파일

Windows에서 다음 명령을 실행합니다.

```powershell
cd desktop
npm install
npm run dist:win
```

결과는 `desktop/release/`에 생성됩니다. 현재 설치 파일은 서명되지 않으므로 Windows SmartScreen 경고가 표시될 수 있습니다.

## 날짜 판정 순서

1. `CAM_YYYYMMDDhhmmss_` 파일명
2. `ffprobe` 메타데이터
3. 파일 생성일 또는 수정일

`ffprobe`는 설정된 경로를 먼저 사용하고, 비어 있으면 `PATH`에서 탐색합니다.

## 안전 규칙

- 복사는 목적지 디렉터리의 임시 파일에 기록한 뒤 최종 이름으로 변경합니다.
- 취소되거나 실패한 임시 파일은 제거합니다.
- 파일 크기만 검사하는 이동 작업도 원본 삭제 전에 MD5를 추가 확인합니다.
- renderer에는 Node.js API나 전체 IPC 객체를 노출하지 않습니다.

## 현재 제한

- 이미지 EXIF 촬영일 파싱은 아직 포함하지 않았습니다. 파일명, `ffprobe`, 파일 시간 순으로 처리합니다.
- 코드 서명과 자동 업데이트는 포함하지 않았습니다.
- NAS/SMB 성능은 네트워크와 서버 설정에 따라 달라집니다.
