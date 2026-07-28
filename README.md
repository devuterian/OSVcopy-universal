# OSVcopy Universal

DJI Osmo 360, Insta360 X 시리즈 등의 `.OSV`, `.INSV`를 포함한 미디어를 촬영 날짜 기준으로 정리하는 데스크톱 importer입니다.

- **macOS:** 기존 SwiftUI/AppKit 앱
- **Windows:** Electron 데스크톱 앱
- **정리 구조:** `YYYY-MM-DD` 또는 `YYYY/YYYY-MM-DD`
- **전송 방식:** 복사, 이동, 미리보기

[![macOS CI](https://github.com/devuterian/osvcopy-universal/actions/workflows/ci.yml/badge.svg)](https://github.com/devuterian/osvcopy-universal/actions/workflows/ci.yml)
[![Windows desktop](https://github.com/devuterian/osvcopy-universal/actions/workflows/windows-desktop.yml/badge.svg)](https://github.com/devuterian/osvcopy-universal/actions/workflows/windows-desktop.yml)
[![Commit standards](https://github.com/devuterian/osvcopy-universal/actions/workflows/commit-standards.yml/badge.svg)](https://github.com/devuterian/osvcopy-universal/actions/workflows/commit-standards.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 주요 기능

- 파일과 여러 폴더 추가, 드래그 앤 드롭
- 하위 폴더 재귀 스캔과 확장자 선택
- 파일명 → `ffprobe` → EXIF/파일 시간 순서의 날짜 판정
- MD5 또는 파일 크기 기반 중복 검사
- 충돌 파일의 `_1`, `_2` 자동 이름 생성
- 진행률, 속도, ETA, 취소, 작업 로그
- NAS와 외장 드라이브 경로 지원
- 이동 모드에서 목적지 검증 전 원본을 삭제하지 않는 안전한 전송

## Windows 다운로드

**Actions → Windows desktop**의 성공한 실행에서 `osvcopy-universal-windows` artifact를 받습니다. Artifact에는 다음 두 파일이 포함됩니다.

- `OSVcopy-Universal-0.1.0-x64.exe`
- `OSVcopy-Universal-0.1.0-x64.zip`

현재 설치 파일은 코드 서명되지 않았으므로 Windows SmartScreen 경고가 표시될 수 있습니다.

## Windows 개발 실행

Node.js 22 이상을 사용합니다.

```bash
cd desktop
npm install
npm start
```

검사와 패키징:

```bash
npm run lint
npm test
npm run dist:win
```

상세 구조와 제한 사항은 [`desktop/README.md`](desktop/README.md)를 확인하세요.

## macOS 빌드

macOS 13 이상과 Swift 5.10 이상이 필요합니다.

```bash
git clone https://github.com/devuterian/osvcopy-universal.git
cd osvcopy-universal
swift build -c release
```

`.app` 번들:

```bash
./build_osvcopy_app.sh
```

DMG:

```bash
./scripts/build_release_dmg.sh
```

파일명에 촬영 날짜가 없을 때 동영상 메타데이터를 사용하려면 `ffprobe`를 설치합니다.

```bash
brew install ffmpeg
```

## 사용 순서

1. 정리할 파일이나 폴더를 추가합니다.
2. 목적지 라이브러리 폴더를 선택합니다.
3. 폴더 구조, 중복 검사, 복사/이동, 확장자를 설정합니다.
4. 미리보기로 결과를 확인한 뒤 실행합니다.

## 주의 사항

- Lightroom이나 카메라 제조사의 공식 편집기를 대체하지 않습니다.
- 네트워크 볼륨의 속도와 안정성은 연결 환경에 따라 달라집니다.
- `ffprobe`가 없으면 일부 동영상은 파일 시간으로 날짜를 판정합니다.
- 중요한 원본은 처음 실행할 때 복사 모드와 미리보기를 사용하세요.

## 프로젝트 구성

```text
Sources/OSVcopy/   SwiftUI macOS 앱
Bundle/            macOS 앱 자산
desktop/           Electron Windows 앱
.github/workflows/ macOS·Windows 빌드와 커밋 검사
records/           저장소 운영 문서
```

## 원본 프로젝트

이 저장소는 [`devuterian/OSVcopy`](https://github.com/devuterian/OSVcopy)를 기반으로 Windows Electron 앱을 추가한 Universal 에디션입니다. 저장소가 별도로 생성되어 GitHub의 fork 네트워크 표시는 연결되지 않습니다.

기여·커밋 규칙은 [`records/REPO.md`](records/REPO.md)와 [`AGENTS.md`](AGENTS.md)를 따릅니다.

## 라이선스

[MIT](LICENSE)
