# War Grid Defense

Godot 4.5 stable + GDScript로 만든 세로형 2D 타워디펜스 원판 데모입니다. 외부 이미지/폰트/오디오 없이 코드 드로잉과 기본 Control만 사용합니다.

## 플레이

1. 녹색 아군 타일을 탭하거나 클릭하면 골드 50을 사용해 타워를 배치합니다.
2. `START WAVE`를 눌러 적을 출현시킵니다.
3. 타워는 사거리 안의 최근접 적에게 자동으로 발사합니다.
4. Core HP 20이 소진되면 패배, 5웨이브를 모두 막으면 승리합니다.

경제는 시작 150 골드, 처치 +10, 웨이브 클리어 +25입니다. 승패 화면의 `RESTART`로 즉시 다시 시작할 수 있습니다.

## 로컬 실행과 검증

Godot 4.5 stable에서 저장소 루트의 `project.godot`을 열고 실행합니다. 마우스와 터치 입력을 모두 지원합니다.

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --path .
```

## Android debug APK 받기

1. GitHub 저장소의 **Actions** 탭을 엽니다.
2. 최신 **Android Debug APK** 실행을 선택합니다.
3. 실행 하단 **Artifacts**에서 `godottest1-debug-apk`를 내려받습니다.
4. 압축 안의 `godottest1.apk`를 Android 기기에 설치합니다.

워크플로는 Godot 4.5, Android SDK/build-tools, export template을 GitHub runner에 설치하고 임시 debug keystore를 생성합니다. 로컬 Android SDK나 저장소 Secret은 필요하지 않습니다.

## 검토 포인트

- 9 x 14 탑다운 보드와 보라색 적군존/녹색 아군존
- 아군 빈 타일 탭 배치, 비용/처치/웨이브 보상
- 최근접 자동 조준과 투사체 피해
- 화이트 피격 플래시, 오렌지 처치 파편/히트스톱, Core 화면 흔들림
- 5웨이브 승리, Core HP 0 패배, 재시작

