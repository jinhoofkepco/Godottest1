# 30대30 개별 판단 AI 전투 실험 결과

이 문서는 `codex/mini-battle-agent-ai` 브랜치의 고정 시드 `230723` 실험 결과입니다. 측정 기준 커밋은 `aff621f`이며, 기존 출시 게임에 합치거나 밸런스를 바꾼 결과가 아닙니다.

## 결론

고정된 30대30 방패병 병목 fixture에서는 개별 유닛의 로컬 판단이 단순 전진 기준선보다 확실히 나았습니다. 120초 동안 실제 공격에 참여한 유닛은 4명에서 60명으로 늘었고, 병리적 대기 누적은 6514.5초에서 201.5초로 96.9% 감소했습니다. 49명이 측면 통로를 통과하고 전열 사망 뒤 14회 교대가 일어나, 후열이 계속 멀뚱히 서 있는 현상을 크게 줄였습니다.

다만 이것은 범용 전투 AI의 완성 증명이 아닙니다. 유닛 60명, 맵 하나, 시드 하나만 비교했고 양 모드 모두 `RED TIME`으로 끝났습니다. 따라서 전투 참여와 병목 해소에는 효과가 있었지만 승률 균형이나 여러 지형에서의 견고성은 아직 검증되지 않았습니다.

## 같은 조건의 120초 비교

두 모드는 지형, 스폰, HP, 피해, 공격 간격과 시드를 공유합니다. `BASELINE`은 중앙 경로와 단순 대기만 사용하고, `AGENT AI`는 각 유닛이 전진·교전·빈자리 채우기·좌우 우회·양보·대기·후퇴를 독립적으로 고릅니다.

| 지표 | BASELINE | AGENT AI |
|---|---:|---:|
| 결과 | RED TIME | RED TIME |
| 종료 시 생존 파랑/빨강 | 30 / 30 | 6 / 9 |
| 한 번이라도 실제 공격한 유닛 | 4 | **60** |
| 전열 교대 | 0 | **14** |
| 중앙선 통과 | 0 | **50** |
| 병리적 대기 누적 | 6514.5초 | **201.5초** |
| 의도적 HOLD 누적 | 0.0초 | 0.2초 |
| 능동 참여율 | 0.07 | **1.00** |

45초 행동 표본의 `AGENT AI` 결과는 다음과 같습니다.

| 지표 | 값 |
|---|---:|
| 우회 결정을 한 유닛 | 55 |
| 양보 결정을 한 유닛 | 36 |
| 측면 통로를 건넌 유닛 | 49 |
| 최대 연속 정체 | 11.5초 |
| 허용 간격 미만 겹침 | 0 |

최대 정체 11.5초는 수용 기준 12초 미만을 통과하지만 여유가 0.5초뿐입니다. 다른 시드와 장애물 배치에서는 다시 측정해야 합니다.

## 개발기 성능

Apple M4 개발기, Godot 4.5 stable .NET, headless 단일 실행에서 각 모드를 3600 고정 틱 측정했습니다. 아래 값은 모바일 기기 프로파일이 아니며, 최악 틱은 OS 스케줄링과 JIT 상태에 민감한 단일 실행값입니다.

| 60유닛, 3600틱 | 평균 틱 | 최악 틱 |
|---|---:|---:|
| BASELINE | 0.113553 ms | 4.216667 ms |
| AGENT AI | **0.040632 ms** | **0.772334 ms** |

두 평균 모두 개발기 목표인 1 ms보다 작습니다. 그러나 이 실험 러너에는 `GC.CollectionCount` 계측이 없으므로 “측정 구간 managed GC 0회”는 증명하지 않았습니다. 고정 틱 내부는 미리 할당한 배열과 공간 버킷을 사용하고 LINQ나 유닛별 컬렉션을 만들지 않지만, 이것을 GC 실측으로 대체해 주장하지 않습니다.

## 수용 기준

| # | 기준 | 판정 | 근거 |
|---:|---|:---:|---|
| 1 | 양측 30명, 대칭 스폰 | PASS | 계약 테스트가 60개 팀·위치와 모든 대칭 쌍을 검증 |
| 2 | 기준선에서 중앙 병목과 비정상 대기 재현 | PASS | 병리적 대기 6514.5초, 실제 공격 4명 |
| 3 | 개별 AI가 우회·양보하고 측면 경로 사용 | PASS | 우회 55명, 양보 36명, 측면 통과 49명 |
| 4 | 기준선보다 대기가 적고 공격 참여가 많음 | PASS | 201.5 < 6514.5초, 60 > 4명 |
| 5 | 능동 참여율 70% 이상 | PASS | 1.00 |
| 6 | 위치 보정 뒤 허용치 미만 겹침 없음 | PASS | 겹침 위반 0 |
| 7 | 120초 안에 결과 또는 타임업 판정 | PASS | 양 모드 모두 120초 `RED TIME` |
| 8 | 개발기 평균 틱 <1 ms 및 managed GC 0회 | **PARTIAL / UNMEASURED** | 평균은 통과했지만 GC 횟수를 계측하지 않음 |

따라서 전체 수용 기준을 모두 통과했다고 보지는 않습니다. 행동 관련 1~7번은 통과했고, 8번은 성능 수치만 통과한 상태입니다.

## 화면에서 확인한 동작

`build/smoke_agent_battle_lab.png`는 540×960 RGBA, 약 80.7KB로 생성됐습니다. 고정 캡처는 9.1초 접촉 장면이며 파랑 29명/빨강 30명, 교전 8명, 실제 공격 참여 18명, 전열 교대 1회 상태입니다.

- 중앙 문에서 첫 접촉이 일어나는 동시에 양측 병력이 좌우 우회로로 나뉘었습니다.
- 방패 외곽의 여덟 가지 색으로 현재 행동을 구분할 수 있고, 흰색 코가 진행 방향을 보여줍니다.
- 공격선과 착탄 링은 실제 공격 타이머가 활성화된 순간에만 표시됩니다.
- 좁은 문과 측면 접촉부에서도 방패 중심이 포개지지 않았습니다.
- HUD, 범례와 다섯 조작 버튼이 세로 화면 밖으로 잘리지 않았습니다.

무인 캡처는 `AGENT AI` 장면 하나만 저장합니다. 기준선의 중앙 정체는 `BASELINE` 버튼으로 직접 비교할 수 있지만 별도 PNG 회귀 산출물은 없습니다.

## 실행과 조작

이 브랜치에서는 프로젝트 기본 장면이 실험실로 지정돼 있습니다. Godot 4.5 .NET 에디터에서 프로젝트를 실행하거나 다음 명령으로 바로 시작합니다.

```bash
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --path .
```

- `AGENT AI`: 개별 판단 모드로 초기화합니다.
- `BASELINE`: 중앙 전진과 단순 대기 모드로 초기화합니다.
- `PAUSE / RESUME`: 시뮬레이션만 정지하거나 재개합니다.
- `1X / 2X`: 진행 속도를 전환합니다.
- `RESET`: 현재 모드와 고정 시드를 처음 상태로 되돌립니다.

방패 테두리는 `ADVANCE / ENGAGE / FILL GAP / FLANK L / FLANK R / YIELD / HOLD / RETREAT`을 뜻합니다. 팀색은 방패 몸체, 행동은 테두리, 진행 방향은 흰색 코로 분리했습니다.

## 재현 명령과 결과

2026-07-23에 아래 순서로 새로 실행했습니다.

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godottest1-dotnet9/dotnet build --nologo

PATH=/private/tmp/godottest1-dotnet9:$PATH \
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . --import --quit

PATH=/private/tmp/godottest1-dotnet9:$PATH \
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_battle_lab.gd

PATH=/private/tmp/godottest1-dotnet9:$PATH \
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_rules.gd

PATH=/private/tmp/godottest1-dotnet9:$PATH \
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --display-driver macos --rendering-method gl_compatibility \
  --audio-driver Dummy --path . -s tests/smoke_agent_battle_lab.gd
```

결과는 C# 빌드 경고 0/오류 0, `AGENT BATTLE LAB TESTS PASS`, 기존 `RULE TESTS PASS`, 화면 캡처 PASS였습니다. import는 종료 코드 0이었고 로컬 Android build-tools 34 fallback 안내와 headless editor-setting 진단 한 줄이 있었지만 리소스 import 실패는 없었습니다.

## 브랜치 검토와 한계

- `main...codex/mini-battle-agent-ai` 차이에서 기존 출시 시뮬레이션, HUD, 씬, Android 워크플로는 바뀌지 않았습니다. 기존 파일 변경은 이 브랜치의 시작 장면을 실험실로 지정한 `project.godot` 한 곳뿐입니다.
- 런타임에는 `AgentBattleSimulation` C# Node 하나만 있고 60개 유닛은 고정 배열 데이터입니다. 유닛 Node, 물리 바디, 시그널과 유닛별 `_process`는 없습니다.
- 고정 틱의 판단·이동·전투는 미리 할당한 배열과 고정 공간 버킷을 사용합니다. `GetSnapshot`/`GetMetrics`의 Dictionary와 배열 복제는 표시 프레임 경계에서 발생하므로 60명 실험에는 충분하지만 대규모 생산 렌더 경계로 그대로 확장하면 안 됩니다.
- 테스트는 한 시드의 행동 회귀에 강하지만 여러 시드, 서로 다른 병목 폭, 복수 장애물, 원거리·대형 유닛과 지형 고도는 다루지 않습니다.
- 양 모드의 `RED TIME`은 팀 방향 또는 타임업 점수 fixture 편향이 남았음을 뜻합니다. 이 실험은 승패 밸런스가 아니라 참여율과 병목 해소 비교로만 해석해야 합니다.
- Android APK/실기기 프레임 시간, 발열, 배터리와 터치 체감은 측정하지 않았습니다.
- 실험은 별도 브랜치에만 있으며 프로덕션 병합은 하지 않았습니다.
