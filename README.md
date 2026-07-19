# Frontline Grid

Godot 4.5 stable + GDScript로 만든 540×960 세로형 아이소메트릭 양군 전선 시뮬레이션입니다. 외부 에셋 없이 모든 타일·유닛·건물·HUD·FX를 코드 도형으로 그립니다. Android 릴리스 메타데이터는 **0.4.0 (version code 3)** 입니다.

## 한 판 규칙과 조작

- 22×44 전장을 위쪽 빨강과 아래쪽 파랑이 나눠 가지며, 180초 안에 적 HQ를 파괴하거나 영토 90%를 확보하면 즉시 승리합니다. 시간 종료 시에는 점유율, HQ 체력 비율, 잔존 병력 체력 순으로 판정합니다.
- 유닛과 건물은 자기 HQ까지 이어지는 열의 보급선을 점유합니다. 한번 전진해 얻은 영토는 부대가 옆 열로 이동해도 유지되고, 상대 진군만 같은 보급선을 다시 덮어 탈환합니다. HUD 점유율과 타일 색은 이 하나의 영속 소유권 배열을 그대로 읽습니다.
- 중앙 14~29행에는 고정 시드로 생성한 16쌍, 총 32개의 대칭 장애물이 있습니다. 장애물은 중립색 돌출 지형으로 보이고 건설·진입할 수 없지만, 그 아래 보급선 소유권은 점유율 계산에 계속 포함됩니다. 유닛은 반발력과 축별 슬라이드로 돌아갑니다.
- 전장 끝에 도착했는데 근처 적이 없으면 반대편 HQ를 장거리 대체 타깃으로 삼아 옆으로도 이동하므로 가장자리에서 멈추지 않습니다.
- 시작 골드는 180, 자동 수입은 초당 3, 처치 보상은 6입니다. 빨강 AI는 14초마다 자기 영토에 최대 4개 스포너를 짓습니다.

파랑 영토의 빈 타일을 짧게 탭/클릭하면 선택한 스포너를 건설합니다. `MELEE 60`과 `RANGED 80` 버튼으로 종류를 고릅니다. 모바일은 두 손가락 핀치로 확대/축소하고 한 손가락 드래그로 이동하며, 데스크톱은 휠 줌과 왼쪽 드래그를 사용합니다. 드래그·핀치는 건설 탭으로 처리되지 않습니다. 확대 범위는 1.0×~2.5×, 시작값은 1.35×입니다.

## 병종과 데이터 구조

| 항목 | 근접 | 원거리 |
|---|---:|---:|
| 스포너 비용 | 60 | 80 |
| HP | 48 | 32 |
| 속도 | 1.45 | 1.25 |
| 사거리 | 0.72 | 2.40 |
| 피해 / 간격 | 1.40 / 0.65초 | 1.00 / 0.90초 |

`BattleSimulation`은 30 Hz 고정 틱과 논리 `(col,row)` 좌표만 사용합니다. 유닛은 종류까지 포함한 정렬된 `PackedArray`들에 저장되며 유닛당 Node·시그널·`_physics_process`가 없습니다. 22×44 팀별 공간 버킷으로 실제 최근접 적 후보를 제한하고, 공격 중에는 정지해 타깃 방향으로 짧게 런지합니다.

렌더러는 팀×병종의 MultiMesh 네 개로 군단을 일괄 처리합니다. 근접병은 넓은 병사 실루엣, 원거리병은 길게 뻗은 발사기 실루엣과 청록색 처리를 사용합니다. 원거리 공격은 밝은 청록-흰색 트레이서와 끝점 스파크로 보입니다. HQ·스포너만 소수 Node2D이며 스포너 지붕 표식도 생산 병종을 구분합니다.

## 피드백과 카메라 안정성

- 교전 타격, 유닛 사망, 생산, 스포너 피격/파괴, 영토 변경, HQ 피격/파괴는 각각 다른 스파크·펄스·파편·스윕·링·붕괴 효과를 냅니다.
- 건설 성공은 파란 다이아몬드, 실패는 빨간 다이아몬드와 X로 표시됩니다.
- HQ 피격과 파괴를 포함한 모든 상황에서 카메라 흔들림과 월드 오프셋은 정확히 0입니다. 가독성은 로컬 플래시, HP 바, 동심원, 붕괴 효과로만 제공합니다.

## 밸런스와 스트레스 결과

자동 밸런스 경로는 파랑이 아무것도 짓지 않을 때 **175.0초 DEFEAT**, 시작 골드로 근접 스포너 3개를 짓고 수입으로 원거리 스포너 1개를 추가할 때 **150.0초 VICTORY**를 기록합니다. 따라서 의도적인 무건설 패배와 실제 혼합 병종 승리가 모두 180초 안에 도달합니다.

2026-07-19 Apple M4, Godot 4.7 stable에서 22개 열 전체에 근접 200기·원거리 200기를 균등 배치하고 30틱 워밍업 뒤 300틱을 측정했습니다. 평균 **9.122 ms**, p95 **12.072 ms**, 최대 **18.328 ms**, 틱당 최대 적 후보 검사 **2,259회**였습니다. 평균과 p95는 60 FPS 예산 16.667 ms 미만이며, 테스트는 후보 검사 12,000회 또는 평균/p95 예산을 넘으면 실패합니다. 최대 단일 틱은 함께 공개하며 Android/CI 절대 시간은 기기에 따라 달라집니다.

## 검증

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/run_stress.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_*.png
```

마지막 명령은 장애물이 보이는 전체 오프닝, 파랑 우세, 파랑 열세, 근접/원거리 전선 혼전의 540×960 PNG 네 장을 `build/smoke_opening.png`, `build/smoke_advantage.png`, `build/smoke_disadvantage.png`, `build/smoke_cluster.png`에 만듭니다. 우세·열세·혼전 장면은 비기본 줌/팬도 함께 검증합니다.

## Android debug APK 받기

항상 같은 주소에서 최신 APK를 바로 받을 수 있습니다: [godottest1.apk 직접 다운로드](https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk)

GitHub Actions 경로는 **Actions → Android Debug APK → 최신 성공 실행 → Artifacts → `godottest1-debug-apk` → `build/godottest1.apk`**입니다. 워크플로가 Godot 4.5 stable, Android SDK/build-tools, export template과 임시 debug keystore를 준비하므로 로컬 Android SDK나 저장소 Secret이 필요하지 않습니다.
