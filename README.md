# War Grid Defense

Godot 4.5 stable + GDScript로 만든 540 x 960 세로형 아이소메트릭 타워디펜스 데모입니다. 외부 이미지·폰트·오디오 없이 코드 드로잉과 기본 Control만 사용합니다.

## 조작

1. 녹색 아군 타일을 탭하거나 마우스 왼쪽 버튼으로 클릭하면 골드 50을 사용해 타워를 배치합니다.
2. 화면 오른쪽 위 `START WAVE` 버튼을 탭하거나 클릭하면 다음 웨이브가 시작됩니다.
3. 타워의 조준과 발사는 자동이며, 승패 화면의 `RESTART` 버튼으로 즉시 다시 시작할 수 있습니다.

## 그대로 유지되는 게임 규칙

- 논리 보드는 9 x 14이며 적은 생성된 열을 따라 코어까지 직선으로 전진합니다.
- 시작 골드 150, 타워 비용 50, 처치 보상 +10, 웨이브 클리어 보상 +25입니다.
- 코어 HP는 20이고 0이 되면 패배하며, 기존 적 수·속도·체력과 타워 피해·연사·사거리를 유지한 5웨이브를 모두 막으면 승리합니다.

## 화면과 게임 로직의 경계

`GridBoard`만 9 x 14 논리 좌표와 64 x 32 크기의 2:1 다이아몬드 화면 좌표를 서로 변환합니다. 이동·사거리·조준·피해·경제·웨이브 판정은 논리 좌표에서 처리하고, 아이소메트릭 투영·화면 맞춤·깊이 정렬은 보기에만 적용됩니다.

## 전투 피드백

- **발사:** 포신 반동, 옅은 총구 다이아몬드, 밝은 청록색 투사체 궤적이 동시에 나타납니다.
- **피격:** 적이 흰색으로 번쩍이고 화면상으로만 밀리며 주황색 피해량이 표시됩니다.
- **처치:** 적이 축소되고 주황색 파편이 퍼지며 약 60 ms 히트스톱이 적용됩니다.
- **누수:** 코어가 빨갛게 번쩍이고 적에서 코어로 붉은 사선이 내려오며 화면이 감쇠 진동합니다.
- **배치:** 성공하면 선택 타일과 사거리 윤곽이 청록색으로, 실패하면 타일과 X 표시가 빨간색으로 나타납니다.
- **웨이브 시작:** 화면 중앙의 `WAVE X` 배너가 짧게 이동하며 사라집니다.

## 로컬 실행과 검증

Godot 4.5 stable에서 저장소 루트의 `project.godot`을 열고 실행합니다. 마우스와 터치 입력을 모두 지원합니다.

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
godot --path .
```

마지막에서 두 번째 명령은 렌더링 픽셀과 무관한 실제 headless 런타임 스모크입니다. Godot의 `--headless` display driver는 dummy 렌더러만 지원하므로 Viewport 픽셀을 PNG로 읽을 수 없습니다.

화면 시각 QA는 상호작용 없이 실행하되 렌더링 가능한 display driver를 사용합니다. macOS 로컬 명령은 다음과 같습니다.

```bash
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_capture.png
```

Linux CI는 Xvfb 안에서 같은 검사를 실행합니다.

```bash
xvfb-run -a -s "-screen 0 540x960x24" godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_capture.png
```

두 경로 모두 ignored 파일인 `build/smoke_capture.png`를 만들며, 캡처 스크립트와 CI는 정확히 540 x 960인지 검사합니다.

## Android debug APK 받기

항상 같은 주소에서 최신 검증 APK를 바로 받을 수 있습니다: [godottest1.apk 직접 다운로드](https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk)

GitHub Actions가 만든 빌드 아티팩트를 받으려면 다음 순서를 따릅니다.

1. GitHub 저장소의 **Actions** 탭을 엽니다.
2. 최신 **Android Debug APK** 워크플로 실행을 선택합니다.
3. 실행 요약 화면 아래 **Artifacts**에서 `godottest1-debug-apk`를 내려받습니다.
4. 내려받은 ZIP을 풀고 안의 `godottest1.apk`를 Android 기기에 설치합니다.

워크플로는 Godot 4.5, Android SDK/build-tools, export template을 GitHub runner에 설치하고 임시 debug keystore를 생성합니다. 로컬 Android SDK나 저장소 Secret은 필요하지 않습니다.

## 검토 포인트

- 9 x 14 아이소메트릭 보드와 보라색 적군존/녹색 아군존
- 아군 빈 타일 탭 배치, 비용/처치/웨이브 보상
- 최근접 자동 조준과 투사체 피해
- 발사·피격·처치·누수·배치·웨이브 시작을 구분하는 색상과 움직임
- 5웨이브 승리, Core HP 0 패배, 재시작
