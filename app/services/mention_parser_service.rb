# frozen_string_literal: true

# 텍스트(코멘트 body, 태스크 title 등)에서 @이름 멘션을 파싱하여 Notification을 생성한다.
# 코멘트와 태스크를 모두 지원 — subject(Comment 또는 Task) + source_text + notification_body_template
class MentionParserService
  # @이름 또는 @John Doe (영문 Title Case 두 단어) 허용.
  # 한글은 단일 토큰으로만 매칭(성+이름 붙여쓰기 관례).
  MENTION_PATTERN = /@([A-Z][a-zA-Z]+(?:[ \t][A-Z][a-zA-Z]+)?|[\w가-힣]+)/.freeze

  # subject: Comment 또는 Task
  # mentioned_by: User
  def initialize(subject, mentioned_by)
    @subject      = subject
    @mentioned_by = mentioned_by
  end

  def call
    return if source_text.blank?

    names = source_text.scan(MENTION_PATTERN).flatten.uniq
    return if names.empty?

    notified_user_ids = []

    names.each do |name|
      mentioned_user = resolve_user(name)
      next unless mentioned_user
      next if notified_user_ids.include?(mentioned_user.id)
      next if mentioned_user == @mentioned_by  # 자기 자신 멘션 스킵

      Notification.create!(
        user:              mentioned_user,
        notifiable:        notifiable_order,
        notification_type: "mentioned",
        title:             notification_title,
        body:              notification_body
      )
      notified_user_ids << mentioned_user.id
    end
  end

  # ISS-353-B (2026-05-10): User 직접 매칭 fallback 추가.
  # 1차: Employee.name → user_id (기존 경로)
  # 2차: User.display_name == name (Employee 미등록 운영 직원 대응)
  # 3차: 두 단어 이름 → 첫 토큰으로 Employee/User 재시도
  def resolve_user(name)
    return nil if name.blank?

    # 1차: Employee 매칭
    if (employee = Employee.find_by(name: name)) && employee.user_id
      return User.find_by(id: employee.user_id)
    end

    # 2차: User.display_name 직접 매칭 (Employee 미등록 직원 대응)
    user = User.find_by(name: name)
    return user if user

    # 3차: 두 단어 이름 → 첫 토큰 재시도
    first_token = name.to_s.split(/\s+/).first
    return nil if first_token.blank? || first_token == name

    if (employee = Employee.find_by(name: first_token)) && employee.user_id
      return User.find_by(id: employee.user_id)
    end
    User.find_by(name: first_token)
  end

  # 하위 호환 — 기존 호출자(있다면)를 위해 유지
  def resolve_employee(name)
    direct = Employee.find_by(name: name)
    return direct if direct
    first_token = name.to_s.split(/\s+/).first
    return nil if first_token.blank? || first_token == name
    Employee.find_by(name: first_token)
  end

  private

  def source_text
    case @subject
    when Comment then @subject.body.to_s
    when Task    then @subject.title.to_s
    else              ""
    end
  end

  def notifiable_order
    case @subject
    when Comment then @subject.order
    when Task    then @subject.order
    end
  end

  def notification_body
    who = @mentioned_by.display_name
    case @subject
    when Comment then "#{who}님이 코멘트에서 회원님을 멘션했습니다."
    when Task    then "#{who}님이 태스크에서 회원님을 멘션했습니다."
    else              "#{who}님이 회원님을 멘션했습니다."
    end
  end

  # ISS-멘션버그: Notification.title 비어 있어 헤더 드롭다운/알림 페이지에 빈 줄로 보이는 문제 수정.
  #   주문 식별자(reference_no/po_no/quo_no/rfq_no/title)가 있으면 그것을 활용, 없으면 일반 문구.
  def notification_title
    order = notifiable_order
    return "@멘션 알림" unless order

    ref = order.po_no.presence || order.quo_no.presence || order.rfq_no.presence ||
          order.reference_no.presence || order.title.presence
    ref ? "@멘션: #{ref}" : "@멘션 알림"
  end
end
