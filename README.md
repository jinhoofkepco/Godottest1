# Frontline Grid

Godot 4.5 stable .NET + C#/GDScript로 만든 540×960 세로형 아이소메트릭 양군 전선 시뮬레이션입니다. 시뮬레이션 코어는 C#, HUD·입력·FX는 GDScript이며 보병·공성병기·드래곤·건물은 CC0 3D 모델을 자체 베이크한 스프라이트입니다. Android 릴리스 메타데이터는 **1.1.0 (version code 10)** 입니다.

## 한 판 규칙과 조작

- 22×44 전장을 위쪽 빨강과 아래쪽 파랑이 나눠 가지며, 180초 안에 적 HQ를 파괴하거나 영토 90%를 확보하면 즉시 승리합니다. 시간 종료 시에는 점유율, HQ 체력 비율, 잔존 병력 체력 순으로 판정합니다.
- 유닛과 건물은 자기 HQ까지 이어지는 열의 보급선을 점유합니다. 한번 전진해 얻은 영토는 부대가 옆 열로 이동해도 유지되고, 상대 진군만 같은 보급선을 다시 덮어 탈환합니다. HUD 점유율과 타일 색은 이 하나의 영속 소유권 배열을 그대로 읽습니다.
- 전 셀은 고정 시드 `PackedByteArray` 고도 0/1/2를 가지며 언덕·정상·절벽이 상하 180° 대칭으로 생성됩니다. 고도차 1은 통행 가능하고 오르막 속도는 0.7배, 고도차 2는 통행 불가 절벽입니다. 별도 장애물 타일은 없으며 생성 직후 모든 배치 후보에서 상대 HQ까지의 경로를 검증합니다.
- 지상군은 상대 HQ에서 역산한 팀별 가중 플로우 필드를 따라 전역 우회합니다. 거리·병력 혼잡·오르막 비용을 합산하고 절벽 전이는 제외하므로 완만한 길을 선호합니다. 건물 건설·파괴 즉시, 그리고 0.75초마다 밀도를 갱신해 한 길이 붐비면 다른 경사로를 선택합니다. 느린 아군이 전방을 막으면 WAIT 상태로 감속하고 길이 열리면 관성 있게 다시 출발합니다.
- 전장 끝에서도 플로우 목표가 상대 HQ이므로 유닛은 자동으로 본진을 찾아가며, 비행 드래곤은 고도·절벽과 건물 충돌을 무시하고 HQ로 직행합니다.
- 고지에서 저지를 공격하면 피해 1.25배, 저지에서 고지는 0.75배, 같은 높이는 1.0배입니다. 원거리 보병은 자기 고도가 1 이상이면 사거리 +0.5셀을 받습니다. 건물은 고도와 무관하게 자기 영토 빈 타일에 건설할 수 있습니다.
- 양측 HQ는 방어탑과 같은 3.6셀 사거리·0.8초 간격으로 자동 방어하며, 한 발 피해는 방어탑 6의 정확히 3배인 18입니다. 근접 보병은 비행 드래곤을 탐지·유지·공격할 수 없고, 원거리병·방어탑·HQ는 대공 공격이 가능합니다.
- 시작 골드는 180, 자동 수입은 초당 3, 처치 보상은 6입니다. 빨강 AI는 14초마다 자기 영토에 최대 3개 스포너를 짓고 근접→원거리→SIEGE를 순환합니다.

파랑 영토의 빈 타일을 짧게 탭/클릭하면 선택한 건물을 건설합니다. `MELEE 60`, `RANGED 80`, `SIEGE 140`, `TOWER 120`, `DRAGON 220`에서 고릅니다. SIEGE는 일반 병력의 3분의 1 생산 속도인 4.8초마다 나오며, 1.2~7.0셀의 밀집 지점을 골라 0.9초 곡사탄을 쏩니다. 예고 링 안 0.9셀을 피해 55.8로 중심 100%→가장자리 40% 공격합니다. 방어탑은 파랑 HQ를 중심으로 한 5×5 범위 안에서만 설치할 수 있으며, 드래곤 레어는 비행 드래곤을 생산합니다. 모바일은 두 손가락 핀치로 확대/축소하고 한 손가락 드래그로 이동하며, 데스크톱은 휠 줌과 왼쪽 드래그를 사용합니다. 드래그·핀치는 건설 탭으로 처리되지 않습니다. 확대 범위는 1.0×~16.0×, 시작값은 1.35×입니다.

## 병종과 데이터 구조

| 항목 | 근접 | 원거리 | SIEGE | 드래곤(비행) |
|---|---:|---:|---:|---:|
| 생산 건물 비용 | 60 | 80 | 140 | 220 |
| HP | 48 | 34 | 40 | 260 |
| 속도 | 1.45 | 1.25 | 0.80 | 1.70 |
| 생산 주기 | 1.6초 | 1.6초 | 4.8초 | 12.5초 |
| 사거리 | 0.72 | 2.2, 고지 2.7 | 1.2~7.0 | 0.9 |
| 반경 | 0.14 | 0.13 | 0.26 | 0.38 |
| 피해 / 간격 | 10 / 0.65초 | 8 / 0.80초 | 55.8 AoE / 3.2초 | 18 / 0.90초 |
| 공격 대상 | 지상만 | 지상+공중 | 지상+공중+건물 | 지상+공중 |

SIEGE는 기존 대비 생산량 3분의 1, 최대 사거리 2배, 공격력 1.8배로 조정했습니다. 일반 사거리와 AoE는 타겟 반경을 포함하며, 아군 오사는 없습니다. 분리는 두 유닛 반경 합×1.2를 목표 간격으로 써 대형 병기가 보병 위에 겹치지 않습니다.

`BattleSimulation.cs`는 30 Hz 고정 틱과 논리 `(col,row)` 좌표만 사용합니다. 유닛은 C# 고정 용량 SoA 배열과 ID 풀에 저장되며 유닛당 Node·시그널·`_physics_process`가 없습니다. SIEGE는 재장전 중 착탄점을 재사용하고 공격 가능 시점에만 밀집 버킷을 다시 탐색합니다. 투사체도 풀링된 지연 데이터이며, 폭발 후보는 상대 팀 공간 버킷만 검사합니다. `TerrainMap.cs`는 고도 생성·대칭·경사 판정·도달성만 맡고 `FlowField.cs`는 팀별 거리+혼잡+오르막 비용과 방향을 캐시합니다. 검증 완료 뒤 GDScript 시뮬레이션 복제본은 삭제해 이중 유지보수를 막았습니다.

렌더러는 전역 Y 정렬 지상군 MultiMesh 하나와 팀별 드래곤 MultiMesh 두 개로 군단을 일괄 처리합니다. 지상군은 보병·CC0 카타펄트 팀별 4-layer Texture2DArray, 드래곤은 팀별 1536×768 아틀라스를 씁니다. 방향은 velocity를 45° 단위로 양자화하고 공격 프레임은 쿨다운·런지와 동기화됩니다. 드래곤은 전용 UV 세로 보정, SIEGE는 per-instance custom data 기반 UV 세로 보정을 적용해 둘 다 바로 섭니다. 모든 병력의 부드러운 타원 그림자는 공유 MultiMesh 하나가 처리합니다. C#이 프레임마다 네 개의 인터리브 `PackedFloat32Array`를 MultiMesh 포맷으로 직접 조립하고, GDScript는 각 버퍼를 `RenderingServer.multimesh_set_buffer` 한 번으로 대입할 뿐 유닛별 getter나 setter를 호출하지 않습니다.

유닛 HP바는 풀피에서 숨고 피해를 입은 순간 3초 표시된 뒤 마지막 0.6초 동안 페이드합니다. 폭과 그림자, 렌더 스케일은 병과별 반경 하나에서 파생되며 발끝 앵커가 논리 좌표와 셀 고도에 접지됩니다. 건물과 HQ의 HP바는 항상 표시됩니다. 영토·체커·그리드는 액터보다 채도와 명도를 낮추고, 높은 타일은 밝은 상판과 어두운 절벽 측면으로 구분합니다. 탭 픽킹은 실제 화면에 보이는 상승 다이아몬드 폴리곤을 검사합니다.

## CC0 모델과 재현 가능한 베이크

- 보병: KayKit Adventurers 1.0의 `Knight.glb`와 `Rogue_Hooded.glb` — `assets/source/kaykit/README.md`
- 드래곤: Quaternius LowPoly Animated Monsters의 `Dragon.fbx` — `assets/source/quaternius_monsters/README.md`
- SIEGE: KayKit Medieval Hexagon Pack 1.0의 팀별 `building_tower_catapult` GLTF에서 재질·팀 부품을 가져오고, 고정 석탑은 제거한 뒤 바퀴·차대·투석팔·버킷을 절차 조립한 이동식 카타펄트 — 범용 베이크 산출물 `assets/units/siege_blue.png`, `siege_red.png`, `siege_atlas.json`
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

## 밸런스와 성능 패스 2

Godot 4.5 자동 밸런스 경로는 파랑이 아무것도 짓지 않을 때 **102.3초 DEFEAT**, 혼합 스포너·방어탑·드래곤을 순차 증설할 때 **108.6초 VICTORY**를 기록합니다. 최신 SIEGE 사거리·피해 상향으로 이전 패스보다 전개가 빨라졌지만 양 경로 모두 HQ 파괴로 명확히 끝납니다. 규칙 테스트는 추가로 인접 열 교전, 최소사거리, 반경 포함 AoE 감쇠, 5기 일괄 피격, 대공 제한과 빨강 AI의 SIEGE 혼합을 고정 틱으로 검증합니다.

2026-07-20 Apple M4의 공식 Godot 4.5 stable에서 GDScript 1단계 결과와 C# 코어를 비교했습니다. C#은 30틱 워밍업 뒤 180틱 동안 같은 근접/원거리/SIEGE 혼합 fixture를 600/1500/3000기로 확장해 측정했습니다.

| 600유닛 측정 | GDScript 패스 1 | C# 패스 2 |
|---|---:|---:|
| 시뮬 틱 평균 | 5.319 ms | **0.691 ms** |
| 시뮬 p95 | 16.198 ms | **1.408 ms** |
| 시뮬 최악 | 22.546 ms | **2.654 ms** |
| 표적 탐색 평균 | 1.090 ms | **0.259 ms** |
| 분리·스티어링 평균 | 1.800 ms | **0.075 ms** |
| 전선·점유율 평균 | 0.029 ms | **0.004 ms** |
| 이벤트 처리 평균 | 0.060 ms | **0.013 ms** |
| 렌더 스냅샷 조립 평균 | 해당 없음 | **0.147 ms** |

| C# 규모 | 틱 평균 | p95 | 최악 | 스냅샷 평균 | GC Gen0/1/2 |
|---|---:|---:|---:|---:|---:|
| 600 | **0.696 ms** | 1.529 ms | 2.291 ms | **0.147 ms** | 0/0/0 |
| 1500 | **1.451 ms** | 2.509 ms | 5.467 ms | **0.254 ms** | 0/0/0 |
| 3000 | **2.605 ms** | 4.140 ms | 13.249 ms | **0.391 ms** | 1/1/0 |

600기 ≤1.5 ms와 3000기 ≤8 ms 평균 목표를 모두 달성했습니다. 패스 3 재측정에서 3000기는 한 차례 Gen0/Gen1 수집과 13.249 ms 최악치가 남았습니다. 주 병목은 표적 탐색 0.957 ms와 분리 0.544 ms이며, 정확 크기 스냅샷·이벤트 배열을 GDScript에 넘기는 경계 할당이 해당 GC의 원인입니다. 평균과 p95는 30 Hz 시뮬 예산 안에 충분히 들어옵니다.

- 영토는 0.2초마다, 건물 이벤트 때는 즉시 공간 버킷으로 갱신하고 점유율도 같은 시점에 캐시합니다.
- 유닛은 3개 그룹을 라운드로빈으로 나눠 표적·분리·혼잡 판단만 스태거링하고, 이동·쿨다운·타격·타겟 생존 검사는 매 틱 유지합니다.
- 고빈도 hit/shot/death는 타입별 PackedArray 소유권 이전 채널을 쓰며, 사소 FX는 프레임당 40개로 제한하고 SIEGE/HQ/승패 이벤트는 제한하지 않습니다. HP바 타이머는 피해 이벤트 때만 갱신합니다.
- 공개 언어 경계는 프레임당 `Step`, `GetRenderSnapshot`, `DrainEvents`, `GetHudSnapshot`, 정수형 `GetBoardVersion`과 필요 시 `TryBuild`/`GetBoardDelta` 벌크 호출만 사용합니다. 전체 `GetBoardSnapshot`은 경기 초기 1회만 호출하며, 테스트 전용 명령·스냅샷도 유닛별 반복 호출 없이 묶어서 전달합니다.
- 프로젝트의 데스크톱·모바일 렌더러는 `gl_compatibility`로 고정돼 있습니다.

## 보드 렌더링 성능 패스 3

현재 맵은 이전 11×22에서 네 배로 확장된 **22×44, 968타일**을 그대로 유지합니다. 타일 상판은 하나의 968-instance `MultiMeshInstance2D`가 처리하며 transform은 초기 한 번만 기록합니다. 절벽 측면은 정적 CanvasItem이 한 번 그린 뒤 다시 만들지 않고, 전선은 캐시된 전용 레이어만 소유권 버전 변경 때 갱신합니다. 소유권 변경은 C#의 변경 인덱스/새 소유자 PackedArray 델타로 전달되어 해당 instance color/custom data만 씁니다. 0.62초 영토 플래시는 타일 custom data의 시작 시간과 셰이더 `TIME`으로 감쇠하므로 셀별 FX 객체와 매 프레임 CPU draw가 없습니다.

2026-07-20 Apple M4, Godot 4.5 stable .NET, OpenGL Compatibility에서 같은 30셀 동시 플립을 3회 워밍업 후 18회 측정했습니다. 변경 전은 968타일 전체 `_draw` 재테셀레이션과 30개 `territory_change` FX, 변경 후는 버전 조회→30셀 델타→MultiMesh instance 갱신과 강제 렌더를 포함합니다.

| 30셀 동시 플립 | 변경 전 전체 draw+FX | 변경 후 delta MultiMesh |
|---|---:|---:|
| 전체 평균 | 10.843 ms | **1.544 ms** |
| 전체 p95 | 11.182 ms | **1.695 ms** |
| 보드 경계 평균 | 0.047 ms | **0.051 ms** |
| 렌더 갱신 평균 | 10.795 ms | **1.491 ms** |
| 렌더 갱신 p95 | 11.134 ms | **1.630 ms** |

렌더 p95는 **85.4% 감소**했고 로컬 목표 ≤2 ms를 달성했습니다. C# 단독 30셀 델타 마샬링은 평균 0.015 ms/p95 0.017 ms였습니다. GitHub 공유 러너의 software-renderer 편차를 고려해 CI 렌더 게이트는 25 ms로 완화하지만, 구조 테스트가 정확히 30개 instance만 갱신되고 전체 sync·transform 재기록·영토 FX 객체가 없음을 별도로 강제합니다.

## 검증

```bash
dotnet build --nologo
godot --headless --path . --import
godot --headless --path . -s tests/run_dotnet_port.gd
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/validate_unit_atlas.gd
godot --headless --path . -s tests/run_stress.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/run_board_stress.gd
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_*.png
```

Godot 4.5 .NET 에디터와 .NET SDK 9 이상이 필요합니다. `run_dotnet_port.gd`는 삭제 전 저장한 GDScript 동일 시드 골든 fixture를 C#에 재생해 0/30/60/120/180틱의 병종별 수, 골드, 점유율, 타이머 결정성을 검증합니다. 마지막 캡처 명령은 셰이더 플래시가 보이는 `smoke_territory_flash.png`, `smoke_large_army.png`, `smoke_siege_impact.png`, 상하 보정된 `smoke_siege_closeup.png`를 포함한 540×960 PNG 열네 장을 만듭니다.

## Android debug APK 받기

이 버전의 GitHub Actions 검증 APK를 바로 받을 수 있습니다: [godottest1 v1.1.0 APK 직접 다운로드](https://github.com/jinhoofkepco/Godottest1/releases/download/v1.1.0/godottest1.apk)

GitHub Actions 경로는 **Actions → Android Debug APK → 최신 성공 실행 → Artifacts → `godottest1-debug-apk` → `build/godottest1.apk`**입니다. 워크플로가 Godot 4.5 stable, Android SDK/build-tools, export template과 임시 debug keystore를 준비하므로 로컬 Android SDK나 저장소 Secret이 필요하지 않습니다.
