# 복수 칸반보드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 단일 구매보드를 복수 칸반보드(구매/영업/PM 등)로 확장하여, 보드별 칼럼·권한·팔레트를 독립 관리하고, Inbox에서 대상 보드를 선택하여 주문을 투입한다.

**Architecture:** `KanbanBoard` 모델을 신규 생성하고, 기존 `CardStatus`와 `Order`에 `kanban_board_id` FK를 추가한다. 기존 데이터는 마이그레이션에서 "구매보드(기본)" 1개로 자동 연결. Settings UI에 보드 CRUD, 칸반 헤더에 보드 선택 콤보박스, `MenuPermission`에 보드별 접근 권한을 추가한다.

**Tech Stack:** Rails 8.1, SQLite3, TailwindCSS CDN, Hotwire Turbo, Alpine.js

---

## File Structure

### 신규 생성
| 파일 | 역할 |
|---|---|
| `db/migrate/YYYYMMDD_create_kanban_boards.rb` | kanban_boards 테이블 + board_id FK on card_statuses/orders |
| `app/models/kanban_board.rb` | KanbanBoard 모델 (has_many :card_statuses, :orders) |
| `app/controllers/settings/kanban_boards_controller.rb` | 보드 CRUD + reorder |
| `app/views/settings/kanban_boards/index.html.erb` | 보드 목록 + 생성/편집 모달 |
| `app/views/settings/kanban_boards/_form_modal.html.erb` | 보드 생성/편집 모달 파셜 |
| `test/models/kanban_board_test.rb` | 모델 테스트 |
| `test/controllers/settings/kanban_boards_controller_test.rb` | 컨트롤러 테스트 |

### 수정
| 파일 | 변경 내용 |
|---|---|
| `app/models/card_status.rb` | `belongs_to :kanban_board` 추가 |
| `app/models/order.rb` | `belongs_to :kanban_board, optional: true` 추가 |
| `app/controllers/kanban_controller.rb` | 보드별 필터링 + 보드 선택 |
| `app/views/kanban/index.html.erb` | 헤더에 보드 선택 콤보박스 |
| `app/controllers/inbox_controller.rb` | convert_to_order에 board_id 파라미터 |
| `app/views/inbox/show.html.erb` | "칸반으로 이동" 시 보드 선택 드롭다운 |
| `app/models/menu_permission.rb` | MENU_KEYS에 보드별 키 동적 추가 OR 별도 board_permissions |
| `config/routes.rb` | settings/kanban_boards 라우트 |
| `app/views/shared/_sidebar.html.erb` | Settings 하위 "칸반 보드 관리" 메뉴 |
| `app/views/settings/card_statuses/index.html.erb` | 보드 선택 필터 추가 |

---

### Task 1: KanbanBoard 모델 + 마이그레이션

**Files:**
- Create: `db/migrate/YYYYMMDD_create_kanban_boards.rb`
- Create: `app/models/kanban_board.rb`
- Modify: `app/models/card_status.rb:1-5`
- Modify: `app/models/order.rb:1-10`
- Test: `test/models/kanban_board_test.rb`

- [ ] **Step 1: 마이그레이션 생성**

```bash
bin/rails generate migration CreateKanbanBoards
```

마이그레이션 파일 내용:
```ruby
class CreateKanbanBoards < ActiveRecord::Migration[8.1]
  def change
    create_table :kanban_boards do |t|
      t.string :name, null: false
      t.string :board_type, default: "custom" # purchase, sales, project, custom
      t.string :description
      t.string :color_palette, default: "corporate" # pastel, vivid, mono, corporate
      t.integer :position, default: 0
      t.boolean :is_default, default: false
      t.references :owner, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_reference :card_statuses, :kanban_board, foreign_key: true, null: true
    add_reference :orders, :kanban_board, foreign_key: true, null: true
    add_index :kanban_boards, :position
  end
end
```

- [ ] **Step 2: 마이그레이션 실행**

```bash
bin/rails db:migrate
```
Expected: 스키마에 kanban_boards 테이블 + card_statuses.kanban_board_id + orders.kanban_board_id

- [ ] **Step 3: KanbanBoard 모델 생성**

```ruby
# app/models/kanban_board.rb
class KanbanBoard < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
  has_many :card_statuses, -> { order(:position) }, dependent: :nullify
  has_many :orders, dependent: :nullify

  validates :name, presence: true, length: { maximum: 50 }
  validates :board_type, inclusion: { in: %w[purchase sales project custom] }
  validates :color_palette, inclusion: { in: %w[pastel vivid mono corporate] }

  scope :ordered, -> { order(:position) }
  scope :default_board, -> { where(is_default: true) }

  def self.ensure_default!
    return if exists?(is_default: true)
    create!(name: "구매보드", board_type: "purchase", is_default: true, position: 0)
  end
end
```

- [ ] **Step 4: CardStatus에 belongs_to 추가**

`app/models/card_status.rb` 상단에 추가:
```ruby
belongs_to :kanban_board, optional: true
```

- [ ] **Step 5: Order에 belongs_to 추가**

`app/models/order.rb` 상단 연관 영역에 추가:
```ruby
belongs_to :kanban_board, optional: true
```

- [ ] **Step 6: 기존 데이터 마이그레이션 seed**

```bash
bin/rails runner "
board = KanbanBoard.create!(name: '구매보드', board_type: 'purchase', is_default: true, position: 0)
CardStatus.where(kanban_board_id: nil).update_all(kanban_board_id: board.id)
Order.where(kanban_board_id: nil).update_all(kanban_board_id: board.id)
puts \"migrated: CardStatus=#{CardStatus.where(kanban_board_id: board.id).count}, Orders=#{Order.where(kanban_board_id: board.id).count}\"
"
```

- [ ] **Step 7: 테스트 작성**

```ruby
# test/models/kanban_board_test.rb
require "test_helper"

class KanbanBoardTest < ActiveSupport::TestCase
  test "validates name presence" do
    board = KanbanBoard.new(board_type: "purchase")
    assert_not board.valid?
    assert_includes board.errors[:name], "can't be blank"
  end

  test "validates board_type inclusion" do
    board = KanbanBoard.new(name: "Test", board_type: "invalid")
    assert_not board.valid?
  end

  test "valid board creates successfully" do
    board = KanbanBoard.new(name: "영업보드", board_type: "sales", color_palette: "vivid")
    assert board.valid?
  end

  test "ensure_default! creates default board" do
    KanbanBoard.destroy_all
    KanbanBoard.ensure_default!
    assert_equal 1, KanbanBoard.where(is_default: true).count
  end

  test "has_many card_statuses" do
    board = KanbanBoard.create!(name: "Test", board_type: "custom")
    assert_respond_to board, :card_statuses
  end

  test "has_many orders" do
    board = KanbanBoard.create!(name: "Test", board_type: "custom")
    assert_respond_to board, :orders
  end
end
```

- [ ] **Step 8: 테스트 실행**

```bash
bin/rails test test/models/kanban_board_test.rb -v
```
Expected: 6 runs, 0 failures

- [ ] **Step 9: 커밋**

```bash
git add db/migrate/ app/models/kanban_board.rb app/models/card_status.rb app/models/order.rb test/models/kanban_board_test.rb db/schema.rb
git commit -m "feat(multi-kanban): KanbanBoard 모델 + 마이그레이션 + 기존 데이터 연결"
```

---

### Task 2: 칸반 헤더에 보드 선택 콤보박스

**Files:**
- Modify: `app/controllers/kanban_controller.rb:8-30` (index 액션)
- Modify: `app/views/kanban/index.html.erb:1-20` (헤더 영역)

- [ ] **Step 1: KanbanController#index에 보드 목록 + 현재 보드 로드**

`app/controllers/kanban_controller.rb` index 액션 상단에 추가:
```ruby
@boards = KanbanBoard.ordered
@current_board = if params[:board_id].present?
  KanbanBoard.find_by(id: params[:board_id])
else
  KanbanBoard.default_board.first
end
@current_board ||= KanbanBoard.ensure_default!
```

기존 `CardStatus.order(:position)` 조회를 보드 필터링으로 변경:
```ruby
# 기존: @card_statuses = CardStatus.order(:position)
@card_statuses = @current_board.card_statuses.order(:position)
```

기존 Order 쿼리에 보드 필터 추가:
```ruby
# 기존 scope에 추가
scope = scope.where(kanban_board_id: @current_board.id)
```

- [ ] **Step 2: 칸반 헤더에 보드 선택 드롭다운 추가**

`app/views/kanban/index.html.erb` 상단 헤더 영역에서 "구매보드" 텍스트를 콤보박스로 교체:
```erb
<div class="flex items-center gap-3">
  <select onchange="window.location.href='/kanban?board_id=' + this.value"
          class="px-3 py-2 bg-white border border-gray-300 rounded-lg text-sm font-semibold text-gray-900 focus:outline-none focus:border-[#00A1E0] focus:ring-1 focus:ring-[#00A1E0]">
    <% @boards.each do |board| %>
      <option value="<%= board.id %>" <%= "selected" if board.id == @current_board.id %>>
        <%= board.name %>
      </option>
    <% end %>
  </select>
</div>
```

- [ ] **Step 3: 수동 테스트**

```bash
bin/rails test test/controllers/kanban_controller_test.rb -v
```
Expected: 기존 칸반 테스트 통과 (board_id 파라미터 없으면 기본 보드 사용)

- [ ] **Step 4: 커밋**

```bash
git add app/controllers/kanban_controller.rb app/views/kanban/index.html.erb
git commit -m "feat(multi-kanban): 칸반 헤더에 보드 선택 콤보박스"
```

---

### Task 3: Settings > 칸반 보드 관리 CRUD

**Files:**
- Create: `app/controllers/settings/kanban_boards_controller.rb`
- Create: `app/views/settings/kanban_boards/index.html.erb`
- Create: `app/views/settings/kanban_boards/_form_modal.html.erb`
- Modify: `config/routes.rb:213-235` (settings 네임스페이스)
- Modify: `app/views/settings/base/index.html.erb` (메뉴 링크)
- Test: `test/controllers/settings/kanban_boards_controller_test.rb`

- [ ] **Step 1: 라우트 추가**

`config/routes.rb` settings 네임스페이스 안에:
```ruby
resources :kanban_boards, except: [:show] do
  member do
    patch :reorder
    post :duplicate
  end
end
```

- [ ] **Step 2: 컨트롤러 생성**

```ruby
# app/controllers/settings/kanban_boards_controller.rb
module Settings
  class KanbanBoardsController < ApplicationController
    before_action :require_admin!
    before_action :set_board, only: %i[edit update destroy reorder duplicate]

    def index
      @boards = KanbanBoard.ordered.includes(:card_statuses)
    end

    def create
      @board = KanbanBoard.new(board_params)
      @board.position = KanbanBoard.maximum(:position).to_i + 1
      @board.owner = current_user
      if @board.save
        redirect_to settings_kanban_boards_path, notice: "보드 '#{@board.name}'이 생성되었습니다."
      else
        @boards = KanbanBoard.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @board.update(board_params)
        redirect_to settings_kanban_boards_path, notice: "보드가 수정되었습니다."
      else
        @boards = KanbanBoard.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      if @board.is_default?
        redirect_to settings_kanban_boards_path, alert: "기본 보드는 삭제할 수 없습니다."
      elsif @board.orders.not_archived.any?
        redirect_to settings_kanban_boards_path, alert: "활성 주문이 있는 보드는 삭제할 수 없습니다."
      else
        @board.destroy
        redirect_to settings_kanban_boards_path, notice: "보드가 삭제되었습니다."
      end
    end

    def reorder
      @board.update!(position: params[:position].to_i)
      head :ok
    end

    def duplicate
      new_board = @board.dup
      new_board.name = "#{@board.name} (복사)"
      new_board.is_default = false
      new_board.position = KanbanBoard.maximum(:position).to_i + 1
      new_board.save!
      @board.card_statuses.each do |cs|
        new_cs = cs.dup
        new_cs.kanban_board = new_board
        new_cs.save!
      end
      redirect_to settings_kanban_boards_path, notice: "보드가 복제되었습니다."
    end

    private

    def set_board
      @board = KanbanBoard.find(params[:id])
    end

    def board_params
      params.require(:kanban_board).permit(:name, :board_type, :description, :color_palette, :is_default)
    end

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근할 수 있습니다." unless current_user&.admin?
    end
  end
end
```

- [ ] **Step 3: index 뷰 생성**

`app/views/settings/kanban_boards/index.html.erb` — 보드 목록 테이블 + 생성/편집 모달. 기존 `settings/card_statuses/index.html.erb` 패턴을 따름:
```erb
<div class="max-w-4xl mx-auto">
  <div class="flex items-center justify-between mb-6">
    <div>
      <h2 class="text-lg font-bold text-gray-900">칸반 보드 관리</h2>
      <p class="text-sm text-gray-500">칸반 보드를 추가하고, 각 보드의 칼럼과 팔레트를 관리합니다.</p>
    </div>
    <button onclick="document.getElementById('board-create-modal').classList.remove('hidden')"
            class="px-4 py-2 text-sm font-medium text-white bg-[#1E3A5F] rounded-lg hover:bg-[#1E3A5F]/90">
      + 새 보드
    </button>
  </div>

  <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
    <table class="w-full text-sm">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-semibold text-gray-600">보드명</th>
          <th class="px-4 py-3 text-left text-xs font-semibold text-gray-600">성격</th>
          <th class="px-4 py-3 text-left text-xs font-semibold text-gray-600">블럭 수</th>
          <th class="px-4 py-3 text-left text-xs font-semibold text-gray-600">팔레트</th>
          <th class="px-4 py-3 text-left text-xs font-semibold text-gray-600">주문 수</th>
          <th class="px-4 py-3 text-right text-xs font-semibold text-gray-600">관리</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% @boards.each do |board| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 font-medium text-gray-900">
              <%= board.name %>
              <% if board.is_default? %>
                <span class="ml-1 text-xs px-1.5 py-0.5 bg-blue-100 text-blue-700 rounded">기본</span>
              <% end %>
            </td>
            <td class="px-4 py-3 text-gray-600"><%= board.board_type %></td>
            <td class="px-4 py-3 text-gray-600"><%= board.card_statuses.size %>개</td>
            <td class="px-4 py-3 text-gray-600"><%= board.color_palette %></td>
            <td class="px-4 py-3 text-gray-600"><%= board.orders.not_archived.count %></td>
            <td class="px-4 py-3 text-right">
              <div class="flex items-center justify-end gap-1">
                <%= link_to settings_card_statuses_path(board_id: board.id),
                    class: "px-2 py-1 text-xs text-gray-600 hover:text-[#00A1E0] border rounded" do %>
                  블럭 관리
                <% end %>
                <button onclick="openBoardEditModal(<%= board.id %>, '<%= j board.name %>', '<%= board.board_type %>', '<%= board.description %>', '<%= board.color_palette %>')"
                        class="px-2 py-1 text-xs text-gray-600 hover:text-[#00A1E0] border rounded">수정</button>
                <% unless board.is_default? %>
                  <%= button_to settings_kanban_board_path(board), method: :delete,
                      data: { turbo_confirm: "보드 '#{board.name}'을 삭제합니까?" },
                      class: "px-2 py-1 text-xs text-red-500 hover:text-red-700 border rounded" do %>
                    삭제
                  <% end %>
                <% end %>
                <%= button_to duplicate_settings_kanban_board_path(board), method: :post,
                    class: "px-2 py-1 text-xs text-gray-600 hover:text-[#00A1E0] border rounded" do %>
                  복제
                <% end %>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

<%# 생성 모달 %>
<div id="board-create-modal" class="hidden fixed inset-0 bg-black/40 z-50 flex items-center justify-center" onclick="if(event.target===this)this.classList.add('hidden')">
  <div class="bg-white rounded-xl shadow-xl w-full max-w-md p-6">
    <h3 class="text-lg font-bold mb-4">새 칸반 보드</h3>
    <%= form_with url: settings_kanban_boards_path, method: :post, local: true do |f| %>
      <div class="space-y-4">
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">보드명</label>
          <%= f.text_field :name, class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm", placeholder: "영업보드", name: "kanban_board[name]" %>
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">성격</label>
          <%= f.select :board_type, [["구매", "purchase"], ["영업", "sales"], ["프로젝트", "project"], ["커스텀", "custom"]],
              {}, class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm bg-white", name: "kanban_board[board_type]" %>
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">설명</label>
          <%= f.text_area :description, class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm", rows: 2, name: "kanban_board[description]" %>
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">컬러 팔레트</label>
          <%= f.select :color_palette, [["Corporate", "corporate"], ["Pastel", "pastel"], ["Vivid", "vivid"], ["Mono", "mono"]],
              {}, class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm bg-white", name: "kanban_board[color_palette]" %>
        </div>
      </div>
      <div class="flex justify-end gap-2 mt-6">
        <button type="button" onclick="this.closest('[id$=-modal]').classList.add('hidden')" class="px-4 py-2 text-sm border rounded-lg">취소</button>
        <%= f.submit "생성", class: "px-4 py-2 text-sm font-medium text-white bg-[#1E3A5F] rounded-lg hover:bg-[#1E3A5F]/90 cursor-pointer" %>
      </div>
    <% end %>
  </div>
</div>

<%# 수정 모달 %>
<div id="board-edit-modal" class="hidden fixed inset-0 bg-black/40 z-50 flex items-center justify-center" onclick="if(event.target===this)this.classList.add('hidden')">
  <div class="bg-white rounded-xl shadow-xl w-full max-w-md p-6">
    <h3 class="text-lg font-bold mb-4">보드 수정</h3>
    <%= form_with url: "#", method: :patch, local: true, id: "board-edit-form" do |f| %>
      <div class="space-y-4">
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">보드명</label>
          <input type="text" name="kanban_board[name]" id="edit-board-name" class="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm" />
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">성격</label>
          <select name="kanban_board[board_type]" id="edit-board-type" class="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm bg-white">
            <option value="purchase">구매</option><option value="sales">영업</option><option value="project">프로젝트</option><option value="custom">커스텀</option>
          </select>
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">설명</label>
          <textarea name="kanban_board[description]" id="edit-board-desc" class="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm" rows="2"></textarea>
        </div>
        <div>
          <label class="block text-xs font-semibold text-gray-600 mb-1.5">컬러 팔레트</label>
          <select name="kanban_board[color_palette]" id="edit-board-palette" class="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm bg-white">
            <option value="corporate">Corporate</option><option value="pastel">Pastel</option><option value="vivid">Vivid</option><option value="mono">Mono</option>
          </select>
        </div>
      </div>
      <div class="flex justify-end gap-2 mt-6">
        <button type="button" onclick="this.closest('[id$=-modal]').classList.add('hidden')" class="px-4 py-2 text-sm border rounded-lg">취소</button>
        <input type="submit" value="저장" class="px-4 py-2 text-sm font-medium text-white bg-[#1E3A5F] rounded-lg hover:bg-[#1E3A5F]/90 cursor-pointer" />
      </div>
    <% end %>
  </div>
</div>

<script>
function openBoardEditModal(id, name, type, desc, palette) {
  document.getElementById('board-edit-form').action = '/settings/kanban_boards/' + id;
  document.getElementById('edit-board-name').value = name;
  document.getElementById('edit-board-type').value = type;
  document.getElementById('edit-board-desc').value = desc || '';
  document.getElementById('edit-board-palette').value = palette;
  document.getElementById('board-edit-modal').classList.remove('hidden');
}
</script>
```

- [ ] **Step 4: Settings 메인에 보드 관리 링크 추가**

`app/views/settings/base/index.html.erb`에서 "칸반 상태 관리" 카드 앞에 추가:
```erb
<a href="<%= settings_kanban_boards_path %>" class="...">칸반 보드 관리</a>
```

- [ ] **Step 5: 테스트 작성**

```ruby
# test/controllers/settings/kanban_boards_controller_test.rb
require "test_helper"

class Settings::KanbanBoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    sign_in @admin
    @board = KanbanBoard.create!(name: "테스트보드", board_type: "custom")
  end

  test "index renders" do
    get settings_kanban_boards_path
    assert_response :success
  end

  test "create board" do
    assert_difference("KanbanBoard.count", 1) do
      post settings_kanban_boards_path, params: { kanban_board: { name: "영업보드", board_type: "sales" } }
    end
    assert_redirected_to settings_kanban_boards_path
  end

  test "update board" do
    patch settings_kanban_board_path(@board), params: { kanban_board: { name: "수정됨" } }
    assert_redirected_to settings_kanban_boards_path
    assert_equal "수정됨", @board.reload.name
  end

  test "cannot delete default board" do
    @board.update!(is_default: true)
    delete settings_kanban_board_path(@board)
    assert_redirected_to settings_kanban_boards_path
    assert KanbanBoard.exists?(@board.id)
  end

  test "duplicate board" do
    assert_difference("KanbanBoard.count", 1) do
      post duplicate_settings_kanban_board_path(@board)
    end
  end
end
```

- [ ] **Step 6: 테스트 실행**

```bash
bin/rails test test/controllers/settings/kanban_boards_controller_test.rb -v
```

- [ ] **Step 7: 커밋**

```bash
git add app/controllers/settings/kanban_boards_controller.rb app/views/settings/kanban_boards/ config/routes.rb app/views/settings/base/index.html.erb test/
git commit -m "feat(multi-kanban): Settings 보드 CRUD + 복제 + 테스트"
```

---

### Task 4: 칸반 상태 관리를 보드별로 분리

**Files:**
- Modify: `app/controllers/settings/card_statuses_controller.rb:1-20`
- Modify: `app/views/settings/card_statuses/index.html.erb:1-10`

- [ ] **Step 1: CardStatusesController에 보드 필터 추가**

index 액션에서:
```ruby
@current_board = if params[:board_id].present?
  KanbanBoard.find(params[:board_id])
else
  KanbanBoard.default_board.first || KanbanBoard.ensure_default!
end
@card_statuses = @current_board.card_statuses.order(:position)
```

create/update/destroy에서 board_id 연결:
```ruby
# create
@card_status = @current_board.card_statuses.build(card_status_params)
```

- [ ] **Step 2: 뷰 상단에 보드 선택 드롭다운**

```erb
<div class="flex items-center gap-3 mb-4">
  <label class="text-sm font-semibold text-gray-600">보드:</label>
  <select onchange="window.location.href='?board_id=' + this.value"
          class="px-3 py-2 border border-gray-300 rounded-lg text-sm bg-white">
    <% KanbanBoard.ordered.each do |board| %>
      <option value="<%= board.id %>" <%= "selected" if board.id == @current_board.id %>><%= board.name %></option>
    <% end %>
  </select>
</div>
```

- [ ] **Step 3: 테스트 실행**

```bash
bin/rails test test/controllers/settings/ -v
```

- [ ] **Step 4: 커밋**

```bash
git add app/controllers/settings/card_statuses_controller.rb app/views/settings/card_statuses/
git commit -m "feat(multi-kanban): 칸반 상태 관리를 보드별 분리"
```

---

### Task 5: Inbox → 칸반 보드 선택

**Files:**
- Modify: `app/controllers/inbox_controller.rb:133-150` (convert_to_order)
- Modify: `app/views/inbox/show.html.erb` (칸반 이동 버튼)

- [ ] **Step 1: convert_to_order에 board_id 파라미터 추가**

```ruby
def convert_to_order
  # 기존 로직 유지 + board_id 설정
  board = if params[:board_id].present?
    KanbanBoard.find_by(id: params[:board_id])
  else
    KanbanBoard.default_board.first
  end
  @order.kanban_board = board
  # ... 기존 status/rfq_status 업데이트 ...
end
```

- [ ] **Step 2: 뷰에서 "칸반으로 이동" 버튼에 보드 선택 드롭다운 추가**

기존 "칸반으로 이동" 버튼/폼을 확인하고, board_id select 추가:
```erb
<%= form_with url: convert_email_to_order_path(@order), method: :post, local: true, class: "flex items-center gap-2" do %>
  <select name="board_id" class="px-3 py-2 border border-gray-300 rounded-lg text-sm bg-white">
    <% KanbanBoard.ordered.each do |board| %>
      <option value="<%= board.id %>" <%= "selected" if board.is_default? %>><%= board.name %></option>
    <% end %>
  </select>
  <button type="submit" class="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-[#1E3A5F] rounded-lg hover:bg-[#1E3A5F]/90">
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
    칸반으로 이동
  </button>
<% end %>
```

- [ ] **Step 3: 테스트 실행**

```bash
bin/rails test test/controllers/inbox_controller_test.rb -v
```

- [ ] **Step 4: 커밋**

```bash
git add app/controllers/inbox_controller.rb app/views/inbox/
git commit -m "feat(multi-kanban): Inbox → 칸반 보드 선택 연동"
```

---

### Task 6: 보드별 접근 권한

**Files:**
- Modify: `app/models/menu_permission.rb` (MENU_KEYS 확장)
- Modify: `app/controllers/kanban_controller.rb` (권한 체크)
- Modify: `app/views/kanban/index.html.erb` (권한 없는 보드 필터)

- [ ] **Step 1: 칸반 권한 체크를 보드별로 확장**

`kanban_controller.rb` index에서:
```ruby
# 사용자가 접근 가능한 보드만 필터
@boards = KanbanBoard.ordered.select { |b| can_access_board?(b) }

# 현재 보드 접근 권한 체크
unless can_access_board?(@current_board)
  redirect_to kanban_path(board_id: @boards.first&.id), alert: "해당 보드에 접근 권한이 없습니다."
  return
end
```

`application_controller.rb`에 헬퍼:
```ruby
def can_access_board?(board)
  return true if current_user&.admin?
  return true if board.owner_id == current_user&.id
  # 기본 보드는 kanban 메뉴 권한이 있으면 접근 가능
  return can_read?(:kanban) if board.is_default?
  # 커스텀 보드는 별도 체크 (향후 BoardPermission 테이블로 확장)
  can_read?(:kanban)
end
helper_method :can_access_board?
```

- [ ] **Step 2: 콤보박스에서 권한 없는 보드 제외**

이미 @boards가 필터링되어 있으므로, 뷰에서 `@boards` 사용.

- [ ] **Step 3: 커밋**

```bash
git add app/controllers/kanban_controller.rb app/controllers/application_controller.rb
git commit -m "feat(multi-kanban): 보드별 접근 권한 체크"
```

---

### Task 7: 대시보드 전체 보드 통합 뷰

**Files:**
- Modify: `app/controllers/dashboard_controller.rb:6-30`
- Modify: `app/views/dashboard/index.html.erb:1-30`

- [ ] **Step 1: 대시보드에 보드별 KPI 요약 추가**

`dashboard_controller.rb`:
```ruby
@board_summaries = KanbanBoard.ordered.map do |board|
  orders = board.orders.not_archived
  {
    board: board,
    total: orders.count,
    new_rfq: orders.where(status: :new_rfq).count,
    in_progress: orders.where.not(status: [:new_rfq, :done, :give_up]).count,
    done: orders.where(status: [:done, :give_up]).count
  }
end
```

- [ ] **Step 2: 뷰 상단에 보드별 미니 카드**

```erb
<div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
  <% @board_summaries.each do |summary| %>
    <a href="<%= kanban_path(board_id: summary[:board].id) %>"
       class="p-4 bg-white rounded-xl border border-gray-200 hover:border-[#00A1E0] transition-colors">
      <p class="text-xs text-gray-500"><%= summary[:board].name %></p>
      <p class="text-2xl font-bold text-gray-900 mt-1"><%= summary[:total] %></p>
      <div class="flex gap-3 mt-2 text-xs">
        <span class="text-blue-600">신규 <%= summary[:new_rfq] %></span>
        <span class="text-amber-600">진행 <%= summary[:in_progress] %></span>
        <span class="text-emerald-600">완료 <%= summary[:done] %></span>
      </div>
    </a>
  <% end %>
</div>
```

- [ ] **Step 3: 커밋**

```bash
git add app/controllers/dashboard_controller.rb app/views/dashboard/index.html.erb
git commit -m "feat(multi-kanban): 대시보드 보드별 KPI 요약 카드"
```

---

### Task 8: 전체 테스트 통과 확인 + 배포

- [ ] **Step 1: 전체 테스트 실행**

```bash
bin/rails test
```
Expected: 0 failures, 0 errors (skips 허용)

- [ ] **Step 2: 회귀 확인**

```bash
bin/rails test test/controllers/kanban_controller_test.rb -v
bin/rails test test/models/ -v
```

- [ ] **Step 3: Production 마이그레이션 + Seed + 배포**

```bash
git add -A && git commit -m "feat(multi-kanban): 복수 칸반보드 v1 완성"
git push
kamal deploy
kamal app exec --reuse "bin/rails db:migrate"
kamal app exec --reuse "bin/rails runner 'board = KanbanBoard.ensure_default!; CardStatus.where(kanban_board_id: nil).update_all(kanban_board_id: board.id); Order.where(kanban_board_id: nil).update_all(kanban_board_id: board.id)'"
```

- [ ] **Step 4: 배포 검증**

```bash
kamal app exec --reuse "bin/rails runner 'puts KanbanBoard.count; puts Order.where(kanban_board_id: nil).count'"
```
Expected: KanbanBoard >= 1, null orders = 0
