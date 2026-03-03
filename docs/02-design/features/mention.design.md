# @사용자 멘션 기능 — Design 문서

**Phase**: Design
**Feature**: mention
**작성일**: 2026-03-03
**담당**: Frontend Architect Agent

---

## 1. 기능 개요

코멘트 입력창과 태스크 제목 입력창에서 `@`를 타이핑하면 팀원 목록 드롭다운이 나타나고,
선택 시 두 가지 효과가 동시에 발생한다:

| 컨텍스트 | 효과 A | 효과 B |
|---------|--------|--------|
| 코멘트 body | `@이름` 텍스트 삽입 | 해당 User에게 `mentioned` 알림 생성 |
| 태스크 add_form | `@이름` 텍스트 삽입 | `assignee_id` hidden input에 User.id 설정 |

---

## 2. 기존 코드 분석 결과

### 2-1. 관련 모델 현황

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :order
  belongs_to :user
  validates :body, presence: true, length: { maximum: 5000 }
  # after_create 콜백 없음 → MentionParserService를 CommentsController에서 호출
end

# app/models/task.rb
class Task < ApplicationRecord
  belongs_to :order
  belongs_to :assignee, class_name: "User", optional: true
  # assignee_id 필드 존재 확인 ✓
end

# app/models/notification.rb
TYPES = %w[due_date status_changed assigned system].freeze
# "mentioned" 타입 추가 필요
```

### 2-2. 기존 컨트롤러 현황

```ruby
# app/controllers/comments_controller.rb
def create
  @comment = @order.comments.build(body: params[:body], user: current_user)
  @comment.save
  # turbo_stream: append + replace
end

# app/controllers/tasks_controller.rb
def task_params
  params.require(:task).permit(:title, :completed, :due_date, :assignee_id, :description)
  # assignee_id 이미 허용됨 ✓
end
```

### 2-3. 기존 Stimulus 컨트롤러 목록

```
autocomplete_controller.js     ← 이 패턴을 mention에서 재활용
bulk_select_controller.js
command_palette_controller.js
department_manager_controller.js
hello_controller.js
inline_edit_controller.js
job_title_manager_controller.js
```

`autocomplete_controller.js`의 드롭다운 렌더링·키보드 네비게이션 패턴을 mention에서 동일하게 적용한다.

### 2-4. 뷰 입력창 위치

- **코멘트 폼**: `app/views/comments/_form.html.erb` — `<textarea name="body">`
- **태스크 폼**: `app/views/tasks/_add_form.html.erb` — `<input name="task[title]">`

---

## 3. 아키텍처 다이어그램

```
사용자 입력 (@키 감지)
       │
       ▼
mention_controller.js (Stimulus)
  ├── onInput(): "@" 이후 쿼리 추출
  ├── fetchSuggestions(q): GET /users/mention_suggestions?q=
  ├── renderDropdown(): position:fixed 드롭다운 렌더
  ├── onSelect(user):
  │     ├── 텍스트 영역에 "@이름 " 삽입
  │     └── [태스크 모드] assignee hidden input에 user.id 설정
  └── closeDropdown()
       │
       ▼
  form submit
       │
       ├── [코멘트] CommentsController#create
       │     └── MentionParserService.parse_and_notify(@comment)
       │           ├── body에서 @이름 패턴 추출
       │           ├── User.find_by(display_name: name)
       │           └── Notification.create!(type: "mentioned", ...)
       │
       └── [태스크] TasksController#create
             └── task_params에 assignee_id 포함 (이미 허용됨)
```

---

## 4. Stimulus `mention_controller.js` 전체 구조

**파일 경로**: `app/javascript/controllers/mention_controller.js`

### 4-1. 컨트롤러 전체 설계

```javascript
// app/javascript/controllers/mention_controller.js
import { Controller } from "@hotwired/stimulus"

/**
 * mention_controller
 *
 * data-controller="mention"
 * data-mention-mode-value="comment | task"   (기본: "comment")
 * data-mention-url-value="/users/mention_suggestions"
 *
 * Targets:
 *   - input      : textarea 또는 text_field (실제 입력창)
 *   - dropdown   : 드롭다운 컨테이너 (position:fixed)
 *   - assignee   : [태스크 모드 전용] hidden input (assignee_id)
 */
export default class extends Controller {
  static values = {
    url:  { type: String, default: "/users/mention_suggestions" },
    mode: { type: String, default: "comment" }   // "comment" | "task"
  }

  static targets = ["input", "dropdown", "assignee"]

  // ── 라이프사이클 ───────────────────────────────────────────
  connect() {
    this._mentionStart  = -1   // "@" 타이핑 시작 커서 위치
    this._query         = ""   // "@" 이후 입력된 검색어
    this._highlighted   = -1   // 드롭다운 하이라이트 인덱스
    this._debounceTimer = null
    this._isOpen        = false

    // 외부 클릭 시 닫기
    this._outsideClick = (e) => {
      if (!this.element.contains(e.target) &&
          !this.dropdownTarget.contains(e.target)) {
        this._closeDropdown()
      }
    }
    document.addEventListener("click", this._outsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick)
    clearTimeout(this._debounceTimer)
    this._closeDropdown()
  }

  // ── 이벤트 핸들러 (data-action으로 연결) ──────────────────

  /**
   * data-action="input->mention#onInput"
   * "@" 감지 → 쿼리 추출 → 드롭다운 요청
   */
  onInput(e) {
    const input    = this.inputTarget
    const cursor   = input.selectionStart
    const text     = input.value.substring(0, cursor)
    const atIndex  = text.lastIndexOf("@")

    if (atIndex === -1) {
      this._closeDropdown()
      return
    }

    // "@" 앞이 공백 또는 줄 시작이어야 멘션 트리거
    const charBefore = text[atIndex - 1]
    if (atIndex > 0 && charBefore !== " " && charBefore !== "\n") {
      this._closeDropdown()
      return
    }

    this._mentionStart = atIndex
    this._query        = text.substring(atIndex + 1)

    // "@" 입력 직후 전체 목록, 이후 쿼리로 필터
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => {
      this._fetchSuggestions(this._query)
    }, this._query.length === 0 ? 0 : 200)
  }

  /**
   * data-action="keydown->mention#onKeydown"
   * 키보드 네비게이션: ArrowUp/Down, Enter, Escape
   */
  onKeydown(e) {
    if (!this._isOpen) return

    const items = this.dropdownTarget.querySelectorAll("[data-mention-item]")
    if (!items.length) return

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        this._highlighted = Math.min(this._highlighted + 1, items.length - 1)
        this._highlight(items)
        break
      case "ArrowUp":
        e.preventDefault()
        this._highlighted = Math.max(this._highlighted - 1, 0)
        this._highlight(items)
        break
      case "Enter":
        if (this._highlighted >= 0 && items[this._highlighted]) {
          e.preventDefault()
          e.stopPropagation()   // form submit 방지
          items[this._highlighted].click()
        }
        break
      case "Escape":
        this._closeDropdown()
        break
      case "Tab":
        this._closeDropdown()
        break
    }
  }

  // ── 아이템 선택 (data-action="click->mention#selectItem") ──

  selectItem(e) {
    const el      = e.currentTarget
    const userId  = el.dataset.userId
    const name    = el.dataset.userName
    const input   = this.inputTarget

    // 입력창 텍스트에서 "@쿼리" 부분을 "@이름 "으로 교체
    const before  = input.value.substring(0, this._mentionStart)
    const after   = input.value.substring(
                      this._mentionStart + 1 + this._query.length
                    )
    input.value   = before + "@" + name + " " + after

    // 커서를 멘션 직후로 이동
    const newCursor = before.length + name.length + 2   // "@" + name + " "
    input.setSelectionRange(newCursor, newCursor)
    input.focus()

    // [태스크 모드] assignee hidden input 설정
    if (this.modeValue === "task" && this.hasAssigneeTarget) {
      this.assigneeTarget.value = userId
    }

    this._closeDropdown()
  }

  // ── Private 메서드 ─────────────────────────────────────────

  _fetchSuggestions(q) {
    const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
    fetch(url, {
      headers: {
        "Accept":           "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(r => r.json())
      .then(users => this._renderDropdown(users))
      .catch(() => this._closeDropdown())
  }

  _renderDropdown(users) {
    this._highlighted = -1

    if (!users.length) {
      this._closeDropdown()
      return
    }

    const html = users.map((u, idx) => `
      <div data-mention-item
           data-user-id="${u.id}"
           data-user-name="${this._esc(u.display_name)}"
           data-action="click->mention#selectItem mouseenter->mention#hoverItem"
           data-idx="${idx}"
           class="flex items-center gap-2.5 px-3 py-2 cursor-pointer
                  hover:bg-blue-50 dark:hover:bg-blue-900/30 transition-colors">
        <div class="w-7 h-7 rounded-full bg-primary text-white text-xs
                    flex items-center justify-center font-bold shrink-0">
          ${this._esc(u.initials)}
        </div>
        <div class="min-w-0">
          <p class="text-sm font-medium text-gray-900 dark:text-white truncate">
            ${this._esc(u.display_name)}
          </p>
          ${u.branch ? `<p class="text-xs text-gray-400 dark:text-gray-500">${this._esc(u.branch_label)}</p>` : ""}
        </div>
      </div>
    `).join("")

    this.dropdownTarget.innerHTML = html
    this._positionDropdown()
    this.dropdownTarget.classList.remove("hidden")
    this._isOpen = true
  }

  hoverItem(e) {
    this._highlighted = parseInt(e.currentTarget.dataset.idx, 10)
    const items = this.dropdownTarget.querySelectorAll("[data-mention-item]")
    this._highlight(items)
  }

  /**
   * 드롭다운 위치 계산 — position:fixed, 커서 캐럿 위치 기준
   * textarea의 경우 Textarea Caret 좌표 라이브러리 없이
   * getBoundingClientRect 기반 하단 고정으로 처리
   */
  _positionDropdown() {
    const input  = this.inputTarget
    const rect   = input.getBoundingClientRect()
    const dd     = this.dropdownTarget

    // 기본: 입력창 하단 왼쪽에 붙임
    let top  = rect.bottom + window.scrollY + 4
    let left = rect.left   + window.scrollX

    // 화면 하단 벗어날 경우 위로 표시
    const ddHeight = 240   // 예상 최대 높이
    if (rect.bottom + ddHeight > window.innerHeight) {
      top = rect.top + window.scrollY - ddHeight - 4
    }

    dd.style.position = "fixed"
    dd.style.top      = `${rect.bottom + 4}px`
    dd.style.left     = `${left}px`
    dd.style.zIndex   = "9999"
    dd.style.width    = "220px"
  }

  _closeDropdown() {
    this.dropdownTarget.classList.add("hidden")
    this.dropdownTarget.innerHTML = ""
    this._isOpen        = false
    this._highlighted   = -1
    this._mentionStart  = -1
    this._query         = ""
  }

  _highlight(items) {
    items.forEach((el, i) => {
      el.classList.toggle("bg-blue-50",       i === this._highlighted)
      el.classList.toggle("dark:bg-blue-900/30", i === this._highlighted)
    })
    if (items[this._highlighted]) {
      items[this._highlighted].scrollIntoView({ block: "nearest" })
    }
  }

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
```

---

## 5. `GET /users/mention_suggestions?q=` 엔드포인트 설계

### 5-1. 라우트 추가

`config/routes.rb`에 다음 추가:

```ruby
# users 네임스페이스 하위 또는 독립 라우트
get "/users/mention_suggestions", to: "users#mention_suggestions"
```

> 기존 `app/controllers/users/` 하위에 세션/omniauth 컨트롤러가 있으므로,
> `UsersController`는 `app/controllers/users_controller.rb`로 새로 생성한다.

### 5-2. UsersController 신규 생성

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  # GET /users/mention_suggestions?q=홍
  # 응답: JSON Array
  # [
  #   { id: 1, display_name: "홍길동", initials: "홍길", branch_label: "서울" },
  #   ...
  # ]
  def mention_suggestions
    q = params[:q].to_s.strip

    users = User.all
    users = users.where("name LIKE :q OR email LIKE :q", q: "%#{q}%") if q.present?
    users = users.limit(8).order(:name)

    render json: users.map { |u|
      {
        id:           u.id,
        display_name: u.display_name,
        initials:     u.initials,
        branch_label: u.branch == "seoul" ? "서울" : "아부다비"
      }
    }
  end
end
```

#### 응답 예시

```json
[
  { "id": 3, "display_name": "홍길동", "initials": "홍길", "branch_label": "서울" },
  { "id": 7, "display_name": "홍길순", "initials": "홍길", "branch_label": "아부다비" }
]
```

#### 보안 고려사항
- `before_action :authenticate_user!` 필수 (미인증 접근 차단)
- `q` 파라미터는 LIKE 쿼리로 처리 — SQL 인젝션은 ActiveRecord의 파라미터 바인딩으로 방어
- 응답에 email/role 등 민감 필드 제외

---

## 6. `MentionParserService` 설계

**파일 경로**: `app/services/mention_parser_service.rb`

```ruby
# app/services/mention_parser_service.rb
#
# 사용법:
#   MentionParserService.parse_and_notify(comment)
#
# - comment.body에서 "@이름" 패턴 추출
# - 매칭되는 User 검색
# - Notification 생성 (type: "mentioned")
# - 자기 자신 멘션은 알림 생략
#
class MentionParserService
  MENTION_REGEX = /@([\w가-힣]+(?:\s[\w가-힣]+)?)/

  # @param comment [Comment] 저장 완료된 Comment 인스턴스
  # @return [Array<Notification>] 생성된 알림 목록
  def self.parse_and_notify(comment)
    new(comment).call
  end

  def initialize(comment)
    @comment  = comment
    @order    = comment.order
    @author   = comment.user
  end

  def call
    mentioned_names = extract_names(@comment.body)
    return [] if mentioned_names.empty?

    mentioned_names.filter_map do |name|
      user = find_user(name)
      next if user.nil?
      next if user == @author   # 자기 자신 멘션 무시

      Notification.create!(
        user:            user,
        notifiable:      @comment,
        notification_type: "mentioned",
        message:         build_message
      )
    end
  end

  private

  def extract_names(body)
    body.scan(MENTION_REGEX).flatten.uniq
  end

  # display_name 또는 name 으로 유저 검색
  def find_user(name)
    User.find_by(name: name) ||
      User.joins(:employee)
          .where(employees: { name: name })
          .first
  end

  def build_message
    "#{@author.display_name}님이 #{@order.title}에서 회원님을 멘션했습니다."
  end
end
```

### Notification 모델 변경 사항

`notification.rb`의 TYPES 상수에 `"mentioned"` 추가:

```ruby
# app/models/notification.rb (변경 전)
TYPES = %w[due_date status_changed assigned system].freeze

# (변경 후)
TYPES = %w[due_date status_changed assigned system mentioned].freeze
```

### CommentsController 연동

```ruby
# app/controllers/comments_controller.rb
def create
  @comment = @order.comments.build(body: params[:body], user: current_user)
  if @comment.save
    # 멘션 파싱 및 알림 생성
    MentionParserService.parse_and_notify(@comment)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("comments-#{@order.id}",
            partial: "comments/comment", locals: { comment: @comment }),
          turbo_stream.replace("comment-form-#{@order.id}",
            partial: "comments/form", locals: { order: @order })
        ]
      end
      format.html { redirect_to @order }
    end
  end
end
```

---

## 7. Task 담당자 자동지정 설계

태스크 모드(`data-mention-mode-value="task"`)에서 `@사용자` 선택 시:

1. 입력창 텍스트에 `@이름 ` 삽입 (코멘트와 동일)
2. `assigneeTarget`(hidden input)에 `user.id` 설정

### 수정된 `_add_form.html.erb`

```erb
<%# app/views/tasks/_add_form.html.erb %>
<div id="task-add-form-<%= order.id %>">
  <%= form_with url: order_tasks_path(order), method: :post,
      data: { controller: "mention",
              mention_mode_value: "task",
              mention_url_value: "/users/mention_suggestions" } do |f| %>
    <div class="flex gap-2 relative">
      <%= f.text_field :title, name: "task[title]",
          placeholder: "새 태스크 추가... (@로 담당자 지정)",
          data: { mention_target: "input",
                  action: "input->mention#onInput keydown->mention#onKeydown" },
          class: "flex-1 px-3 py-2 border border-gray-200 dark:border-gray-600
                  bg-white dark:bg-gray-800 text-gray-900 dark:text-white
                  rounded-lg text-sm focus:ring-2 focus:ring-accent/30 outline-none" %>
      <%= f.hidden_field :assignee_id,
          data: { mention_target: "assignee" } %>
      <%= f.submit "추가",
          class: "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300
                  text-sm px-3 py-2 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600
                  cursor-pointer whitespace-nowrap" %>
    </div>
    <%# 드롭다운 컨테이너 — position:fixed로 z-index 최상위 %>
    <div data-mention-target="dropdown"
         class="hidden fixed bg-white dark:bg-gray-800 border border-gray-200
                dark:border-gray-700 rounded-lg shadow-lg overflow-hidden
                max-h-60 overflow-y-auto"
         style="z-index: 9999; width: 220px;">
    </div>
  <% end %>
</div>
```

---

## 8. 드롭다운 HTML 구조

```html
<!-- position:fixed, z-index:9999, 입력창 하단 4px -->
<div
  data-mention-target="dropdown"
  class="hidden fixed bg-white dark:bg-gray-800
         border border-gray-200 dark:border-gray-700
         rounded-lg shadow-lg overflow-hidden
         max-h-60 overflow-y-auto"
  style="z-index: 9999; width: 220px;"
>
  <!-- 항목 1 -->
  <div
    data-mention-item
    data-user-id="3"
    data-user-name="홍길동"
    data-action="click->mention#selectItem mouseenter->mention#hoverItem"
    data-idx="0"
    class="flex items-center gap-2.5 px-3 py-2 cursor-pointer
           hover:bg-blue-50 dark:hover:bg-blue-900/30 transition-colors"
  >
    <div class="w-7 h-7 rounded-full bg-primary text-white text-xs
                flex items-center justify-center font-bold shrink-0">
      홍길
    </div>
    <div class="min-w-0">
      <p class="text-sm font-medium text-gray-900 dark:text-white truncate">
        홍길동
      </p>
      <p class="text-xs text-gray-400 dark:text-gray-500">서울</p>
    </div>
  </div>
  <!-- 항목 2 ... -->
</div>
```

### 디자인 토큰 적용

| 속성 | 값 | 이유 |
|-----|-----|-----|
| `background` | `#FFFFFF` / `gray-800` | Surface 토큰 |
| `border` | `gray-200` / `gray-700` | 기존 드로어와 동일 |
| `border-radius` | `rounded-lg` (8px) | 기존 카드 반경 |
| `shadow` | `shadow-lg` | 플로팅 요소 구분 |
| `hover bg` | `blue-50` / `blue-900/30` | Accent 계열 연강조 |
| `아바타 bg` | `bg-primary` (#1E3A5F) | 기존 assignee 아바타와 통일 |
| `z-index` | `9999` | 드로어(z-10) 위에 표시 |
| `width` | `220px` | 이름 2줄 넘침 없는 최소 너비 |

---

## 9. 수정된 코멘트 폼

```erb
<%# app/views/comments/_form.html.erb %>
<div id="comment-form-<%= order.id %>">
  <%= form_with url: order_comments_path(order), method: :post,
      data: { controller: "mention",
              mention_mode_value: "comment",
              mention_url_value: "/users/mention_suggestions" } do |f| %>
    <div class="flex gap-3">
      <div class="w-7 h-7 rounded-full bg-primary text-white text-xs
                  flex items-center justify-center font-bold shrink-0 mt-0.5">
        <%= current_user.initials %>
      </div>
      <div class="flex-1 space-y-2 relative">
        <%= f.text_area :body,
            placeholder: "코멘트를 입력하세요... (@로 팀원 멘션)",
            rows: 2,
            data: { mention_target: "input",
                    action: "input->mention#onInput keydown->mention#onKeydown" },
            class: "w-full px-3 py-2 border border-gray-200 dark:border-gray-600
                    bg-white dark:bg-gray-800 text-gray-900 dark:text-white
                    rounded-lg text-sm focus:ring-2 focus:ring-accent/30
                    outline-none resize-none" %>
        <%# 드롭다운 컨테이너 %>
        <div data-mention-target="dropdown"
             class="hidden fixed bg-white dark:bg-gray-800 border border-gray-200
                    dark:border-gray-700 rounded-lg shadow-lg overflow-hidden
                    max-h-60 overflow-y-auto"
             style="z-index: 9999; width: 220px;">
        </div>
        <div class="flex justify-end">
          <%= f.submit "등록",
              class: "bg-accent text-white text-sm px-4 py-1.5 rounded-lg
                      hover:bg-accent/90 cursor-pointer" %>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

---

## 10. 구현 체크리스트 (5단계)

### Step 1: 백엔드 준비 (30분)
- [ ] `config/routes.rb`에 `get "/users/mention_suggestions"` 추가
- [ ] `app/controllers/users_controller.rb` 생성 (`mention_suggestions` 액션)
- [ ] `app/models/notification.rb` TYPES에 `"mentioned"` 추가
- [ ] `app/services/mention_parser_service.rb` 생성
- [ ] `bin/rails routes | grep mention` 으로 라우트 확인

### Step 2: Stimulus 컨트롤러 구현 (45분)
- [ ] `app/javascript/controllers/mention_controller.js` 생성
- [ ] `app/javascript/controllers/index.js`에 import 추가
- [ ] `onInput` — `@` 감지 및 쿼리 추출 로직 검증
- [ ] `_fetchSuggestions` — fetch 호출 및 JSON 파싱 검증
- [ ] `selectItem` — 텍스트 삽입 및 assignee 설정 검증

### Step 3: 뷰 수정 (20분)
- [ ] `app/views/comments/_form.html.erb` — `data-controller="mention"` 추가
- [ ] `app/views/tasks/_add_form.html.erb` — `data-mention-mode-value="task"` 추가
- [ ] 두 파일 모두 드롭다운 컨테이너 div 추가

### Step 4: CommentsController 연동 (15분)
- [ ] `create` 액션에 `MentionParserService.parse_and_notify(@comment)` 추가
- [ ] `bin/rails runner "MentionParserService.parse_and_notify(Comment.last)"` 스모크 테스트

### Step 5: 통합 테스트 (30분)
- [ ] 코멘트 폼: `@홍` 입력 → 드롭다운 표시 확인
- [ ] 키보드 ArrowDown/Enter로 선택 → `@홍길동 ` 텍스트 삽입 확인
- [ ] 폼 제출 → Notification 생성 확인 (`bin/rails console`: `Notification.last`)
- [ ] 태스크 폼: `@홍길동` 선택 → `assignee_id` hidden input 값 설정 확인
- [ ] 태스크 저장 후 `Task.last.assignee` 확인
- [ ] 자기 자신 멘션 시 알림 미생성 확인

---

## 11. 파일 변경 요약

| 파일 | 변경 종류 | 내용 |
|-----|----------|------|
| `config/routes.rb` | 수정 | `get "/users/mention_suggestions"` 추가 |
| `app/controllers/users_controller.rb` | 신규 생성 | `mention_suggestions` 액션 |
| `app/services/mention_parser_service.rb` | 신규 생성 | 멘션 파싱 + Notification 생성 |
| `app/models/notification.rb` | 수정 | TYPES에 `"mentioned"` 추가 |
| `app/controllers/comments_controller.rb` | 수정 | `create`에 MentionParserService 호출 |
| `app/javascript/controllers/mention_controller.js` | 신규 생성 | Stimulus 멘션 컨트롤러 |
| `app/javascript/controllers/index.js` | 수정 | mention 컨트롤러 import |
| `app/views/comments/_form.html.erb` | 수정 | mention 컨트롤러 연결 |
| `app/views/tasks/_add_form.html.erb` | 수정 | mention 컨트롤러 + assignee hidden 추가 |

---

## 12. 리스크 및 고려사항

| 리스크 | 대응 방법 |
|--------|----------|
| display_name에 공백 포함 시 MENTION_REGEX 불일치 | `[\w가-힣]+(?:\s[\w가-힣]+)?` 패턴으로 성+공백+이름 커버 |
| 동명이인 멘션 알림 중복 | `extract_names` 후 `.uniq` 처리 + 첫 번째 매칭 User만 알림 |
| position:fixed 드롭다운이 모달/드로어 밖으로 나올 경우 | `z-index: 9999` 설정, 드로어 z-index(z-50)보다 높게 설정 |
| textarea 스크롤 시 드롭다운 위치 어긋남 | scroll 이벤트에서 `_closeDropdown()` 호출 추가 검토 |
| 기존 `autocomplete_controller`와 스타일 불일치 | 동일한 아바타/hover 클래스 사용으로 통일 |
