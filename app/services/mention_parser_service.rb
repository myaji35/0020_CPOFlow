# frozen_string_literal: true

# Comment body에서 @이름 멘션을 파싱하여 Notification을 생성한다.
class MentionParserService
  MENTION_PATTERN = /@([\w가-힣]+(?:\s[\w가-힣]+)?)/.freeze

  def initialize(comment, mentioned_by)
    @comment      = comment
    @mentioned_by = mentioned_by
  end

  def call
    names = @comment.body.to_s.scan(MENTION_PATTERN).flatten.uniq
    return if names.empty?

    names.each do |name|
      employee = Employee.find_by("name = ?", name)
      next unless employee&.user_id

      mentioned_user = User.find_by(id: employee.user_id)
      next unless mentioned_user
      next if mentioned_user == @mentioned_by  # 자기 자신 멘션 스킵

      Notification.create!(
        user:              mentioned_user,
        notifiable:        @comment.order,
        notification_type: "mentioned",
        message:           "#{@mentioned_by.display_name}님이 코멘트에서 회원님을 멘션했습니다."
      )
    end
  end
end
