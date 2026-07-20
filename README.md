# Frontline Grid

Godot 4.5 stable + GDScript로 만든 540×960 세로형 아이소메트릭 양군 전선 시뮬레이션입니다. HUD·지형·FX는 코드 도형이며, 보병·공성병기·드래곤·건물은 CC0 3D 모델을 자체 베이크한 스프라이트입니다. Android 릴리스 메타데이터는 **0.9.0 (version code 8)** 입니다.

## 한 판 규칙과 조작

- 22×44 전장을 위쪽 빨강과 아래쪽 파랑이 나눠 가지며, 180초 안에 적 HQ를 파괴하거나 영토 90%를 확보하면 즉시 승리합니다. 시간 종료 시에는 점유율, HQ 체력 비율, 잔존 병력 체력 순으로 판정합니다.
- 유닛과 건물은 자기 HQ까지 이어지는 열의 보급선을 점유합니다. 한번 전진해 얻은 영토는 부대가 옆 열로 이동해도 유지되고, 상대 진군만 같은 보급선을 다시 덮어 탈환합니다. HUD 점유율과 타일 색은 이 하나의 영속 소유권 배열을 그대로 읽습니다.
- 전 셀은 고정 시드 `PackedByteArray` 고도 0/1/2를 가지며 언덕·정상·절벽이 상하 180° 대칭으로 생성됩니다. 고도차 1은 통행 가능하고 오르막 속도는 0.7배, 고도차 2는 통행 불가 절벽입니다. 별도 장애물 타일은 없으며 생성 직후 모든 배치 후보에서 상대 HQ까지의 경로를 검증합니다.
- 지상군은 상대 HQ에서 역산한 팀별 가중 플로우 필드를 따라 전역 우회합니다. 거리·병력 혼잡·오르막 비용을 합산하고 절벽 전이는 제외하므로 완만한 길을 선호합니다. 건물 건설·파괴 즉시, 그리고 0.75초마다 밀도를 갱신해 한 길이 붐비면 다른 경사로를 선택합니다. 느린 아군이 전방을 막으면 WAIT 상태로 감속하고 길이 열리면 관성 있게 다시 출발합니다.
- 전장 끝에서도 플로우 목표가 상대 HQ이므로 유닛은 자동으로 본진을 찾아가며, 비행 드래곤은 고도·절벽과 건물 충돌을 무시하고 HQ로 직행합니다.
- 고지에서 저지를 공격하면 피해 1.25배, 저지에서 고지는 0.75배, 같은 높이는 1.0배입니다. 원거리 보병은 자기 고도가 1 이상이면 사거리 +0.5셀을 받습니다. 건물은 고도와 무관하게 자기 영토 빈 타일에 건설할 수 있습니다.
- 양측 HQ는 방어탑과 같은 3.6셀 사거리·0.8초 간격으로 자동 방어하며, 한 발 피해는 방어탑 6의 정확히 3배인 18입니다. 근접 보병은 비행 드래곤을 탐지·유지·공격할 수 없고, 원거리병·방어탑·HQ는 대공 공격이 가능합니다.
- 시작 골드는 180, 자동 수입은 초당 3, 처치 보상은 6입니다. 빨강 AI는 14초마다 자기 영토에 최대 3개 스포너를 짓고 근접→원거리→SIEGE를 순환합니다.

파랑 영토의 빈 타일을 짧게 탭/클릭하면 선택한 건물을 건설합니다. `MELEE 60`, `RANGED 80`, `SIEGE 140`, `TOWER 120`, `DRAGON 220`에서 고릅니다. SIEGE는 1.2~3.5셀의 밀집 지점을 골라 0.9초 곡사탄을 쏘고, 예고 링 안 0.9셀을 중심 100%→가장자리 40%로 공격합니다. 방어탑은 파랑 HQ를 중심으로 한 5×5 범위 안에서만 설치할 수 있으며, 드래곤 레어는 비행 드래곤을 생산합니다. 모바일은 두 손가락 핀치로 확대/축소하고 한 손가락 드래그로 이동하며, 데스크톱은 휠 줌과 왼쪽 드래그를 사용합니다. 드래그·핀치는 건설 탭으로 처리되지 않습니다. 확대 범위는 1.0×~16.0×, 시작값은 1.35×입니다.

## 병종과 데이터 구조

| 항목 | 근접 | 원거리 | SIEGE | 드래곤(비행) |
|---|---:|---:|---:|---:|
| 생산 건물 비용 | 60 | 80 | 140 | 220 |
| HP | 48 | 34 | 40 | 260 |
| 속도 | 1.45 | 1.25 | 0.80 | 1.70 |
| 사거리 | 0.72 | 2.2, 고지 2.7 | 1.2~3.5 | 0.9 |
| 반경 | 0.14 | 0.13 | 0.26 | 0.38 |
| 피해 / 간격 | 10 / 0.65초 | 8 / 0.80초 | 31 AoE / 3.2초 | 18 / 0.90초 |
| 공격 대상 | 지상만 | 지상+공중 | 지상+공중+건물 | 지상+공중 |

SIEGE 피해 31은 제시 시작값 26에서 실제 고정 틱 상성을 맞추기 위해 허용 범위 안인 +19.2%로 조정했습니다. 일반 사거리와 AoE는 타겟 반경을 포함하며, 아군 오사는 없습니다. 분리는 두 유닛 반경 합×1.2를 목표 간격으로 써 대형 병기가 보병 위에 겹치지 않습니다.

`BattleSimulation`은 30 Hz 고정 틱과 논리 `(col,row)` 좌표만 사용합니다. 위치·속도·HP·상태·반경·SIEGE 착탄점까지 정렬된 `PackedArray`들에 저장되며 유닛당 Node·시그널·`_physics_process`가 없습니다. SIEGE는 재장전 중 착탄점을 재사용하고 공격 가능 시점에만 밀집 버킷을 다시 탐색합니다. 투사체도 지연 딕셔너리 데이터이며, 폭발 후보는 상대 팀 공간 버킷만 검사합니다. `TerrainMap`은 고도 생성·대칭·경사 판정·도달성만 맡고 `FlowField`는 팀별 거리+혼잡+오르막 비용과 방향을 캐시합니다.

렌더러는 전역 Y 정렬 지상군 MultiMesh 하나와 팀별 드래곤 MultiMesh 두 개로 군단을 일괄 처리합니다. 지상군은 보병·CC0 카타펄트 팀별 4-layer Texture2DArray, 드래곤은 팀별 1536×768 아틀라스를 씁니다. 방향은 packed velocity를 45° 단위로 양자화하고 공격 프레임은 쿨다운·런지와 동기화됩니다. 드래곤 전용 셰이더가 프레임 UV의 세로축만 뒤집어 베이크 시트가 상하 반전되지 않고 똑바로 표시됩니다. 모든 병력의 부드러운 타원 그림자는 공유 MultiMesh 하나가 처리합니다.

유닛 HP바는 풀피에서 숨고 피해를 입은 순간 3초 표시된 뒤 마지막 0.6초 동안 페이드합니다. 폭과 그림자, 렌더 스케일은 병과별 반경 하나에서 파생되며 발끝 앵커가 논리 좌표와 셀 고도에 접지됩니다. 건물과 HQ의 HP바는 항상 표시됩니다. 영토·체커·그리드는 액터보다 채도와 명도를 낮추고, 높은 타일은 밝은 상판과 어두운 절벽 측면으로 구분합니다. 탭 픽킹은 실제 화면에 보이는 상승 다이아몬드 폴리곤을 검사합니다.

## CC0 모델과 재현 가능한 베이크

- 보병: KayKit Adventurers 1.0의 `Knight.glb`와 `Rogue_Hooded.glb` — `assets/source/kaykit/README.md`
- 드래곤: Quaternius LowPoly Animated Monsters의 `Dragon.fbx` — `assets/source/quaternius_monsters/README.md`
- SIEGE: KayKit Medieval Hexagon Pack 1.0의 팀별 `building_tower_catapult` GLTF — 범용 베이크 산출물 `assets/units/siege_blue.png`, `siege_red.png`, `siege_atlas.json`
- 건물·보관 프랍: KayKit Medieval Hexagon Pack 1.0의 성·병영·궁술장·공성탑·타워·바위·상자 — `assets/source/kaykit_medieval/README.md` (현재 전장 차단은 프랍이 아니라 고도 절벽이 담당)
- 모든 원본은 각 폴더의 `LICENSE.txt`에 명시된 CC0 1.0 Universal이며 정확한 공식 URL과 upstream revision/download 파일을 함께 기록했습니다.

`tools/sprite_baker/bake_sprites.gd`는 모델·애니메이션·방향·카메라·셀·팀·출력을 인자로 받는 범용 Godot CLI입니다. 좌상단 45° 키라이트와 약한 앰비언트로 명암을 보존합니다. `bake_world_sprites.gd`는 건물·드래곤을, `bake_siege_sprites.gd`는 같은 규약의 8방향 `idle/walk/attack/death` 카타펄트 팀 시트를 만듭니다. 모든 시트는 2048² 이내이며 재실행법은 `tools/sprite_baker/README.md`에 있습니다.

## 피드백과 카메라 안정성

- 교전 타격, 유닛 사망, 생산, 스포너 피격/파괴, 영토 변경, HQ 피격/파괴는 각각 다른 스파크·펄스·파편·스윕·링·붕괴 효과를 냅니다.
- 고지→저지 공격은 같은 타격 타이밍을 유지하면서 스파크만 1.32배 크고 더 밝아 전투 보정을 즉시 구분할 수 있습니다.
- 건설 성공은 파란 다이아몬드, 실패는 빨간 다이아몬드와 X로 표시됩니다.
- HQ 피격과 파괴를 포함한 모든 상황에서 카메라 흔들림과 월드 오프셋은 정확히 0입니다. 가독성은 로컬 플래시, HP 바, 동심원, 붕괴 효과로만 제공합니다.
- 방어탑과 HQ 자동 방어는 긴 밝은 트레이서, 드래곤 생산은 레어의 확장 펄스와 날개 실루엣으로 구분됩니다.
- SIEGE 발사는 비행시간 내내 주황 착탄 링, 지면 그림자와 분리된 포물선 탄체로 보이며 착탄은 흰 중심 플래시·확장 주황 링·흙먼지 파편으로 일반 타격과 구분됩니다.

## 밸런스와 스트레스 결과

Godot 4.5 자동 밸런스 경로는 파랑이 아무것도 짓지 않을 때 **122.1초 DEFEAT**, 시작 골드로 근접 스포너 3개를 짓고 수입으로 원거리·드래곤 생산을 보강할 때 **130.8초 VICTORY**를 기록합니다. 규칙 테스트는 추가로 ①근접 2기의 밀집 피해 교환은 SIEGE 우세 ②같은 병력이 흩어지면 근접 우세 ③최소사거리 안에서는 SIEGE 패배 ④드래곤은 스플래시를 맞고도 1:1 승리 ⑤빨강 AI의 세 번째 건물이 SIEGE임을 고정 틱으로 검증합니다.

2026-07-20 Apple M4의 Godot 4.5 stable에서 근접 200기·원거리 200기·SIEGE 200기, 총 **600기**와 실제 곡사/착탄을 포함해 30틱 워밍업 뒤 300틱을 측정했습니다. 평균 **9.820 ms**, p95 **20.052 ms**, 최대 **30.588 ms**, 틱당 최대 일반 표적 후보 **1,355회**, 동시 127발 착탄에서도 AoE 후보는 발당 최대 **50.9회**, SIEGE 발사 **584회**·착탄 **563회**였습니다. 로컬 평균 16.667 ms/p95 30 ms 게이트를 통과하며, GitHub 공유 러너는 평균 30 ms/p95 55 ms를 사용합니다.

## 검증

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/validate_unit_atlas.gd
godot --headless --path . -s tests/run_stress.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_*.png
```

마지막 명령은 기존 열 장에 `smoke_large_army.png`(진영당 100기)와 `smoke_siege_impact.png`(카타펄트·텔레그래프·포물선·폭발)를 더한 540×960 PNG 열두 장을 만듭니다. 자동 검증은 고도/픽킹, 상하가 바른 드래곤, 반경 기반 크기·분리·피격, SIEGE 최소사거리·AoE 감쇠·무오사·AI 혼합까지 검사합니다.

## Android debug APK 받기

항상 같은 주소에서 최신 APK를 바로 받을 수 있습니다: [godottest1.apk 직접 다운로드](https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk)

GitHub Actions 경로는 **Actions → Android Debug APK → 최신 성공 실행 → Artifacts → `godottest1-debug-apk` → `build/godottest1.apk`**입니다. 워크플로가 Godot 4.5 stable, Android SDK/build-tools, export template과 임시 debug keystore를 준비하므로 로컬 Android SDK나 저장소 Secret이 필요하지 않습니다.
