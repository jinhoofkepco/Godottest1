# Frontline Grid

Godot 4.5 stable + GDScript로 만든 540×960 세로형 아이소메트릭 양군 전선 시뮬레이션입니다. 외부 에셋 없이 모든 타일·유닛·건물·HUD·FX를 코드 도형으로 그립니다.

## 한 판 규칙과 조작

- 11×22 전장을 위쪽 빨강과 아래쪽 파랑이 나눠 가지며, 최상단/최하단 HQ 중 하나가 파괴되면 즉시 끝납니다.
- 파랑 영토의 빈 타일을 터치하거나 클릭하면 골드 60으로 스포너를 짓습니다. 시작 골드는 180, 자동 수입은 초당 3, 유닛 처치 보상은 6입니다.
- 빨강 AI도 14초 간격으로 전선 가까운 자기 영토에 최대 4개 스포너를 증설합니다.
- 스포너가 만든 근접 유닛은 자동 진군·탐색·교전합니다. 90% 점유, HQ 파괴, 또는 3분 타임업 우세 판정으로 승패가 결정됩니다.
- 스포너를 짓지 않으면 빨강 증원에 밀려 패배하고, 중앙 파랑 스포너를 지으면 적 HQ까지 돌파해 승리할 수 있도록 자동 규칙 테스트로 두 경로를 검증합니다.

## 로직과 렌더링 경계

`BattleSimulation`은 30 Hz 고정 틱에서 논리 `(col,row)` 좌표만 사용합니다. 유닛은 `PackedInt32Array`, `PackedVector2Array`, `PackedFloat32Array` 등 구조별 배열에 저장되며 유닛당 Node·시그널·`_physics_process`가 없습니다. 타깃 탐색은 11×22 그리드 버킷만 확인합니다.

`GridBoard`만 논리 좌표와 64×32 2:1 아이소 화면 좌표를 변환하고 역변환하여 입력을 픽킹합니다. 화면의 군단은 빨강/파랑 `MultiMeshInstance2D` 두 개로 일괄 렌더링하고, 수가 적은 HQ/스포너만 Node2D를 사용합니다. 타일 색과 HUD 점유율은 같은 소유권 배열에서 읽습니다.

## 전투 피드백 자가검증

1. **교전 타격:** 흰 방사형 스파크와 주황 중심점으로 짧고 날카롭게 표시됩니다.
2. **유닛 사망:** 팀 색 원형 팝이 퍼지고 사각 파편이 흩어져 일반 타격과 구분됩니다.
3. **스포너 생산:** 팀 색 원형 펄스와 위로 솟는 빔으로 증원 시점을 알립니다.
4. **스포너 피격/파괴:** 피격은 흰 테두리+붉은 사선, 파괴는 블록 붕괴+파편으로 서로 구분됩니다.
5. **전선 이동:** 소유권이 바뀐 다이아몬드 위를 팀 색 스윕이 통과하고 실제 타일색이 전환됩니다.
6. **HQ 피격:** 다른 FX보다 큰 동심원·사선 플래시와 강한 감쇠 화면 흔들림이 발생합니다.

건설 성공은 파란 다이아몬드, 실패는 빨간 다이아몬드와 X로 표시됩니다. 파랑/빨강 팀은 타일·유닛·건물·점유율 바 전체에 동일하게 적용됩니다.

## 검증과 스트레스 결과

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/run_stress.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
```

2026-07-19 Apple M4, Godot 4.7 stable 로컬 측정에서 데이터 유닛 400개·300틱은 평균 **1.234 ms**, p95 **4.367 ms**, 최대 버킷 후보 검사 **22,815회**였습니다. 30 Hz 틱 예산 33.333 ms보다 낮으며, 테스트는 평균과 p95가 이 예산을 넘으면 실패합니다. Android/CI의 절대 수치는 기기에 따라 달라집니다.

렌더 가능한 로컬 환경에서는 다음 명령이 초반/파랑 우세/파랑 열세 세 장을 각각 540×960 PNG로 만듭니다.

```bash
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
```

Linux CI는 같은 스크립트를 Xvfb에서 실행하며 `build/smoke_opening.png`, `build/smoke_advantage.png`, `build/smoke_disadvantage.png`를 확인합니다.

## Android debug APK 받기

항상 같은 주소에서 최신 APK를 바로 받을 수 있습니다: [godottest1.apk 직접 다운로드](https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk)

GitHub Actions 빌드는 저장소의 **Actions → Android Debug APK → 최신 성공 실행 → Artifacts → `godottest1-debug-apk`**에서 받을 수 있습니다. 워크플로가 Godot 4.5 stable, Android SDK/build-tools, export template과 임시 debug keystore를 준비하므로 로컬 Android SDK나 저장소 Secret이 필요하지 않습니다.
