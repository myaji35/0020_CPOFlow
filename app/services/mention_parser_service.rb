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
      employee = resolve_employee(name)
      next unless employee&.user_id
      next if notified_user_ids.include?(employee.user_id)

      mentioned_user = User.find_by(id: employee.user_id)
      next unless mentioned_user
      next if mentioned_user == @mentioned_by  # 자기 자신 멘션 스킵

      Notification.create!(
        user:              mentioned_user,
        notifiable:        notifiable_order,
        notification_type: "mentioned",
        body:              notification_body
      )
      notified_user_ids << mentioned_user.id
    end
  end

  # "홍길동멘션테스트 그리고" 처럼 뒤 단어까지 캡처된 경우 → 첫 토큰으로 재조회.
  # "John Doe" 처럼 실제 두 단어 이름이면 전체 매칭 우선, 없으면 첫 단어만.
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
end
