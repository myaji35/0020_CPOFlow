# Design: order-drawer-enhancement

## 1. 태스크 Turbo Frame 인라인 토글

### TasksController#update
```ruby
respond_to do |format|
  format.turbo_stream {
    render turbo_stream: [
      turbo_stream.replace("task-#{@task.id}", partial: "tasks/task", locals: { task: @task, order: @order }),
      turbo_stream.replace("task-progress-#{@order.id}", partial: "tasks/progress", locals: { order: @order })
    ]
  }
  format.html { redirect_back fallback_location: order_path(@order) }
end
```

### partials
- `app/views/tasks/_task.html.erb` — 단일 태스크 행 (turbo-frame id="task-{id}")
- `app/views/tasks/_progress.html.erb` — 진행률 바 (id="task-progress-{order.id}")

### ERB 변경 (_drawer_content.html.erb 태스크 섹션)
```erb
<div id="task-progress-<%= order.id %>">
  <%= render "tasks/progress", order: order %>
</div>
<div class="space-y-1 mb-4">
  <% tasks.each do |task| %>
    <%= render "tasks/task", task: task, order: order %>
  <% end %>
</div>
```

## 2. 코멘트 Turbo Stream

### CommentsController#create
```ruby
respond_to do |format|
  format.turbo_stream {
    render turbo_stream: [
      turbo_stream.append("comments-#{@order.id}", partial: "comments/comment", locals: { comment: @comment }),
      turbo_stream.replace("comment-form-#{@order.id}", partial: "comments/form", locals: { order: @order })
    ]
  }
  format.html { redirect_back fallback_location: order_path(@order) }
end
```

### partials
- `app/views/comments/_comment.html.erb` — 단일 코멘트 행
- `app/views/comments/_form.html.erb` — 코멘트 작성 폼 (초기화용)

### ERB 변경 (_drawer_content.html.erb 코멘트 섹션)
```erb
<div id="comments-<%= order.id %>" class="space-y-4 mb-5">
  <%= render order.comments.chronological.includes(:user), locals: { order: order } %>
</div>
<div id="comment-form-<%= order.id %>">
  <%= render "comments/form", order: order %>
</div>
```

## 3. 활동 로그 타임라인 UI

### 아이콘/컬러 매핑
| action | 아이콘 | 컬러 |
|--------|--------|------|
| status_changed | 화살표 | accent(blue) |
| comment_added | 말풍선 | gray |
| task_completed | 체크 | green |
| created | 플러스 | primary(navy) |

### 구조
```erb
<div class="relative pl-6">
  <div class="absolute left-2 top-0 bottom-0 w-px bg-gray-100 dark:bg-gray-700"></div>
  <% activities.each do |act| %>
    <div class="relative mb-4">
      <!-- 아이콘 원 (타임라인 점) -->
      <!-- 텍스트: 유저명 + 행동 + 시간 -->
      <!-- 상태변경 시: from→to 배지 -->
    </div>
  <% end %>
</div>
```

## 파일 목록

| 파일 | 변경 |
|------|------|
| `app/controllers/tasks_controller.rb` | turbo_stream 응답 추가 |
| `app/controllers/comments_controller.rb` | turbo_stream 응답 추가 |
| `app/views/tasks/_task.html.erb` | 신규 partial |
| `app/views/tasks/_progress.html.erb` | 신규 partial |
| `app/views/comments/_comment.html.erb` | 신규 partial |
| `app/views/comments/_form.html.erb` | 신규 partial |
| `app/views/orders/_drawer_content.html.erb` | 태스크/코멘트/활동 섹션 수정 |
