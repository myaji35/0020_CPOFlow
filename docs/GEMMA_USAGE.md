# Gemma 4 E4B — 이 프로젝트에서 쓰는 법

## 상태
- 모델: `gemma4:e4b` (9.6GB, Q4_K_M, 멀티모달, 128K 컨텍스트)
- 엔드포인트: `http://localhost:11434`
- 저장 위치: `/Volumes/E_SSD/ollama-models`
- 클라이언트: `lib/gemma.rb`

## 서버 기동 확인
```bash
pgrep ollama || OLLAMA_MODELS=/Volumes/E_SSD/ollama-models nohup ollama serve > /tmp/ollama.log 2>&1 &
```

## 용도별 호출 패턴

### 1. PDF / 문서 OCR
1페이지씩 이미지로 변환 후 `gemma.ocr(path)`.
`pdftoppm`이나 `poppler`로 PDF → PNG 변환 권장.

### 2. 명함 OCR (Townin)
`gemma.parseBusinessCard(path)` 또는 `gemma.parse_business_card(path)`.
반환: `{name, company, title, phone, email, address}` JSON.

### 3. InsureGraph 챗봇 보조
RAG 검색 후 청크를 프롬프트에 주입:
```
system: 보험 도메인 전문가. 한국어로 답변.
prompt: 컨텍스트:\n{chunks}\n\n질문: {user_input}
```

### 4. 의사결정 규칙
1. OCR/문서 파싱 → Gemma 4 우선 (오프라인, 비용 0)
2. 한국어 대화 품질 결정적 → Claude API 기본, Gemma fallback
3. 대량 배치 → Gemma 1차 필터 후 중요 건만 Claude 승급

## 트러블슈팅
- `ollama list`에 모델 없음 → `OLLAMA_MODELS=/Volumes/E_SSD/ollama-models ollama pull gemma4:e4b`
- 서버 응답 없음 → `lsof -ti:11434` 로 포트 확인, 기존 프로세스 kill 후 재기동
- 이미지 OCR 느림 → `options.num_ctx` 낮추기, 이미지 해상도 2000px 이하로 축소
