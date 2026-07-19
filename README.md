# Frontline Grid

Godot 4.5 stable + GDScript로 만든 540×960 세로형 아이소메트릭 양군 전선 시뮬레이션입니다. 외부 에셋 없이 모든 타일·유닛·건물·HUD·FX를 코드 도형으로 그립니다. Android 릴리스 메타데이터는 **0.5.0 (version code 4)** 입니다.

## 한 판 규칙과 조작

- 22×44 전장을 위쪽 빨강과 아래쪽 파랑이 나눠 가지며, 180초 안에 적 HQ를 파괴하거나 영토 90%를 확보하면 즉시 승리합니다. 시간 종료 시에는 점유율, HQ 체력 비율, 잔존 병력 체력 순으로 판정합니다.
- 유닛과 건물은 자기 HQ까지 이어지는 열의 보급선을 점유합니다. 한번 전진해 얻은 영토는 부대가 옆 열로 이동해도 유지되고, 상대 진군만 같은 보급선을 다시 덮어 탈환합니다. HUD 점유율과 타일 색은 이 하나의 영속 소유권 배열을 그대로 읽습니다.
- 중앙 14~29행에는 고정 시드로 생성한 16쌍, 총 32개의 대칭 장애물이 있습니다. 장애물은 중립색 돌출 지형으로 보이고 건설·지상군 진입은 불가능하지만, 그 아래 보급선 소유권은 점유율 계산에 계속 포함됩니다.
- 지상군은 상대 HQ에서 역산한 팀별 가중 플로우 필드를 따라 전역 우회합니다. 건물 건설·파괴 즉시, 그리고 0.75초마다 갱신되는 병력 밀도 비용 때문에 한 틈이 붐비면 다른 틈을 선택합니다. 느린 아군이 전방을 막으면 WAIT 상태로 감속하고, 길이 열리면 관성 있게 다시 출발합니다.
- 전장 끝에서도 플로우 목표가 상대 HQ이므로 유닛은 자동으로 본진을 찾아가며, 비행 드래곤은 장애물과 건물 충돌을 무시하고 HQ로 직행합니다.
- 시작 골드는 180, 자동 수입은 초당 3, 처치 보상은 6입니다. 빨강 AI는 14초마다 자기 영토에 최대 3개 스포너를 짓습니다.

파랑 영토의 빈 타일을 짧게 탭/클릭하면 선택한 건물을 건설합니다. `MELEE 60`, `RANGED 80`, `TOWER 120`, `DRAGON 220`에서 고릅니다. 방어탑은 파랑 HQ를 중심으로 한 5×5 범위 안에서만 설치할 수 있으며, 드래곤 레어는 비행 드래곤을 생산합니다. 모바일은 두 손가락 핀치로 확대/축소하고 한 손가락 드래그로 이동하며, 데스크톱은 휠 줌과 왼쪽 드래그를 사용합니다. 드래그·핀치는 건설 탭으로 처리되지 않습니다. 절차 도형이 선명하게 유지되는 확대 범위는 1.0×~16.0×, 시작값은 1.35×입니다.

## 병종과 데이터 구조

| 항목 | 근접 | 원거리 | 드래곤(비행) |
|---|---:|---:|---:|
| 생산 건물 비용 | 60 | 80 | 220 |
| HP | 48 | 32 | 90 |
| 속도 | 1.45 | 1.25 | 1.70 |
| 사거리 | 0.72 | 2.40 | 0.95 |
| 피해 / 간격 | 1.65 / 0.65초 | 1.20 / 0.90초 | 4.50 / 0.80초 |

`BattleSimulation`은 30 Hz 고정 틱과 논리 `(col,row)` 좌표만 사용합니다. 위치·속도·HP·상태·고정 경로 편향까지 정렬된 `PackedArray`들에 저장되며 유닛당 Node·시그널·`_physics_process`가 없습니다. 22×44 팀별 공간 버킷으로 최근접 적, 분리, WAIT, 혼잡 밀도를 제한합니다. `FlowField`는 팀마다 `PackedFloat32Array` 비용과 `PackedVector2Array` 방향을 캐시하며, 혼잡 재계산은 두 팀을 엇갈려 실행해 주기적 스파이크를 줄입니다.

렌더러는 팀×3병종의 MultiMesh 여섯 개로 군단을 일괄 처리합니다. 근접병, 긴 발사기의 원거리병, 넓은 날개의 드래곤 실루엣이 즉시 구분됩니다. WAIT는 어두운 색, 공격은 런지, 원거리와 방어탑 공격은 밝은 트레이서로 표시합니다. HQ·스포너·방어탑·드래곤 레어만 소수 Node2D이며 각각 십자 HQ, 병종 지붕, 포신, 주황 날개 형태로 구분합니다.

## 피드백과 카메라 안정성

- 교전 타격, 유닛 사망, 생산, 스포너 피격/파괴, 영토 변경, HQ 피격/파괴는 각각 다른 스파크·펄스·파편·스윕·링·붕괴 효과를 냅니다.
- 건설 성공은 파란 다이아몬드, 실패는 빨간 다이아몬드와 X로 표시됩니다.
- HQ 피격과 파괴를 포함한 모든 상황에서 카메라 흔들림과 월드 오프셋은 정확히 0입니다. 가독성은 로컬 플래시, HP 바, 동심원, 붕괴 효과로만 제공합니다.
- 방어탑 발사는 긴 흰색 트레이서, 드래곤 생산은 레어의 확장 펄스와 날개 실루엣으로 구분됩니다.

## 밸런스와 스트레스 결과

자동 밸런스 경로는 파랑이 아무것도 짓지 않을 때 **180.0초 DEFEAT**, 시작 골드로 근접 스포너 3개를 짓고 수입으로 원거리 스포너와 드래곤 레어를 보강할 때 **180.0초 VICTORY**를 기록합니다. 따라서 의도적인 무건설 패배와 지상·비행 혼합 승리가 모두 2~3분 범위에서 도달합니다.

2026-07-20 Apple M4, Godot 4.7 stable에서 22개 열 전체에 근접 200기·원거리 200기를 균등 배치하고 팀별 혼잡 플로우 재계산까지 포함해 30틱 워밍업 뒤 300틱을 측정했습니다. 평균 **13.832 ms**, p95 **24.375 ms**, 최대 **38.686 ms**, 틱당 최대 적 후보 검사 **837회**였습니다. 로컬 게이트는 평균 16.667 ms 미만, 주기 재계산을 포함한 p95 30 ms 미만, 후보 검사 12,000회 미만입니다. p95는 30 Hz 시뮬레이션의 33.333 ms 틱 기한보다 낮으며, 최대 단일 틱도 숨기지 않고 함께 기록합니다. GitHub 호스티드 러너는 기기 편차를 고려해 평균/p95 모두 30 ms 게이트를 사용합니다.

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

마지막 명령은 전체 오프닝(방어탑·드래곤 레어 포함), 파랑 우세, 파랑 열세, 전선 혼전, 영속 측면 점유, 두 병목으로 분산되는 플로우 장면의 540×960 PNG 여섯 장을 `build/smoke_opening.png`, `build/smoke_advantage.png`, `build/smoke_disadvantage.png`, `build/smoke_cluster.png`, `build/smoke_persistent_flank.png`, `build/smoke_flow_split.png`에 만듭니다.

## Android debug APK 받기

항상 같은 주소에서 최신 APK를 바로 받을 수 있습니다: [godottest1.apk 직접 다운로드](https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk)

GitHub Actions 경로는 **Actions → Android Debug APK → 최신 성공 실행 → Artifacts → `godottest1-debug-apk` → `build/godottest1.apk`**입니다. 워크플로가 Godot 4.5 stable, Android SDK/build-tools, export template과 임시 debug keystore를 준비하므로 로컬 Android SDK나 저장소 Secret이 필요하지 않습니다.
