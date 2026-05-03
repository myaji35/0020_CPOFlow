# 점검 ↔ CLI 구현 자동 트리거 프로토콜

CPOFlow에서 Claude(점검) ↔ Claude Code CLI(구현) 사이 자동 알림 메커니즘.

## 작동 흐름

```
     [Claude / 점검 측]                       [Claude Code CLI / 구현 측]
                                                          
   1. 운영 검수 + 갭 발견                                  
            ↓                                              
   2. docs/audit-*.md 작성                                 
            ↓                                              
   3. audit-trigger-cli.sh 호출 ────────────►  4. SessionStart audit-detect.sh
        (P0~P3 트리거 발송)                          ↓                       
            ↓                                       5. INBOX.txt 출력 자동 노출
   .claude/cli-trigger/queue/*.json                     "🔍 미검수 N건"        
   .claude/cli-trigger/INBOX.txt                            ↓                  
                                                       6. cli-pickup-triggers.sh
                                                            ↓                  
                                                       7. "구현해~ 개발해~"   
                                                            ↓                  
                                                       8. 코드 작성·커밋·push 
                                                            ↓                  
                                                       9. cli-pickup-triggers.sh --done
                                                            ↓                  
                                                       (큐 → done/ 이동)       
            ↑                                                                  
   10. 다음 SessionStart에서 audit-detect.sh ◄──── (origin/main 새 커밋 감지) 
        "🔍 미검수 커밋 N개"                                                   
            ↓                                                                  
   11. 검수 → 11번부터 반복                                                    
```

## Hook 파일

| 파일 | 호출 측 | 역할 |
|---|---|---|
| `.claude/hooks/audit-detect.sh` | 양쪽 SessionStart | origin/main 새 커밋 감지 출력 |
| `.claude/hooks/audit-mark-reviewed.sh` | 점검 측 | 검수 완료 SHA 기록 |
| `.claude/hooks/audit-trigger-cli.sh` | 점검 측 | 새 이슈 → CLI 픽업 큐 |
| `.claude/hooks/cli-pickup-triggers.sh` | CLI 측 | 큐 픽업 + "구현해~" 명령 출력 |

## 디렉터리 구조

```
.claude/
├── audit-log.json                      # 검수 완료 SHA 기록 (점검 측)
└── cli-trigger/
    ├── INBOX.txt                       # 트리거 통합 텍스트 (cat으로 빠르게 읽음)
    ├── queue/                          # 미픽업 트리거 (json 1개 = 이슈 1개)
    ├── picked/                         # 픽업 후 처리 중
    └── done/                           # 처리 완료
```

## 트리거 JSON 스키마

```json
{
  "issue_id": "AUDIT-002-FU",
  "title": "Client/Supplier default_assignee 시드 + 폼 강화",
  "priority": "P0",
  "file": "docs/audit-2026-05-03-followup.md",
  "created_at": "2026-05-03T05:05:38Z",
  "command": "구현해~ 개발해~ AUDIT-002-FU: ...",
  "status": "pending"
}
```

## 사용 명령

### 점검 측 (Claude)

```bash
# 새 이슈 트리거 발송
bash .claude/hooks/audit-trigger-cli.sh <issue_id> "<title>" <P0|P1|P2|P3> <file_path>

# CLI 구현 검수 완료 표시
bash .claude/hooks/audit-mark-reviewed.sh <SHA|--all-current>
```

### CLI 측 (Claude Code CLI / Codex)

```bash
# 픽업 (모든 우선순위 정렬됨)
bash .claude/hooks/cli-pickup-triggers.sh

# 단일 이슈 완료 처리
bash .claude/hooks/cli-pickup-triggers.sh --done <issue_id>
```

### 어느 쪽이든 빠른 확인

```bash
# 큐에 뭐가 있는지 한 줄로 보기
cat .claude/cli-trigger/INBOX.txt
```

## SessionStart 자동 감지

`settings.json`의 SessionStart hook에 `audit-detect.sh`가 등록되어 있어 **세션 시작 시 자동 실행**됨. 새 커밋이 있으면 출력에 "🔍 미검수 커밋 N개 발견"이 표시됨. 없으면 silent.

## .gitignore

`.claude/audit-log.json`과 `.claude/cli-trigger/`는 **로컬 상태**라 git 추적 안 함. 양쪽이 각자의 머신에서 별도 큐 운영.

## 운영 권고

1. **점검 측**: 검수 완료 후 `audit-mark-reviewed.sh --all-current` 한 번만 실행하면 origin/main 현재 HEAD까지 모두 reviewed로 표시됨
2. **CLI 측**: SessionStart 출력에서 INBOX 발견 → 즉시 `cli-pickup-triggers.sh`
3. **양쪽 동기화 필요 없음**: 각자 자기 audit-log.json만 관리. 큐는 양쪽이 같은 디렉터리(`.claude/cli-trigger/`)를 보면서 file system 으로 통신.
