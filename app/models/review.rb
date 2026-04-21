# frozen_string_literal: true

class Review < ApplicationRecord
  # status enum — "new"는 Ruby 예약어 느낌이므로 new_review 로 내부 사용
  enum :status, {
    new_review: 0,
    triaged:    1,
    responded:  2,
    archived:   3
  }, prefix: false

  enum :channel, {
    in_app: "in_app",
    email:  "email"
  }, prefix: false

  # Validations
  validates :rating, inclusion: {
    in: 1..5,
    message: "을(를) 1~5 사이로 선택해 주세요."
  }
  validates :body,   presence: true, length: { minimum: 5, maximum: 4000 }

  # 공개 노출용 status 문자열 ("new_review" → "new", 나머지는 그대로)
  def status_public
    status == "new_review" ? "new" : status
  end

  # 입력값 "new" → "new_review" 변환 세터 (API/폼 입력 호환)
  def status=(val)
    mapped = val.to_s == "new" ? "new_review" : val
    super(mapped)
  end

  # JSON 직렬화용 해시 (email 원문 제외)
  def to_review_json
    {
      id:         "RV-#{id.to_s.rjust(3, '0')}",
      rating:     rating,
      body:       body,
      email:      nil,
      email_hash: email_hash,
      status:     status_public,
      created_at: created_at&.iso8601,
      channel:    channel,
      user_agent: user_agent
    }
  end
end
