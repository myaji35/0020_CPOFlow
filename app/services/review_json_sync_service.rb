# frozen_string_literal: true

# ReviewJsonSyncService
# .claude/review-db/reviews.json 파일과 DB 레코드를 동기화
# - append: 새 리뷰를 JSON에 추가
# - update: 상태 변경 등 기존 레코드 업데이트
class ReviewJsonSyncService
  # 프로젝트 루트 기준 .claude/review-db/reviews.json 경로
  # Rails 앱이 프로젝트 루트에 바로 있으므로 Rails.root 사용
  JSON_PATH = Rails.root.join(".claude", "review-db", "reviews.json").freeze

  def initialize
    ensure_file!
  end

  # 새 리뷰를 JSON 파일에 append
  def append(review)
    sync do |data|
      data["reviews"].reject! { |r| r["id"] == review_id(review) }
      data["reviews"] << review.to_review_json.stringify_keys
    end
  end

  # 기존 리뷰 업데이트 (상태 전환 등)
  def update(review)
    sync do |data|
      idx = data["reviews"].index { |r| r["id"] == review_id(review) }
      if idx
        data["reviews"][idx] = review.to_review_json.stringify_keys
      else
        data["reviews"] << review.to_review_json.stringify_keys
      end
    end
  end

  private

  def review_id(review)
    "RV-#{review.id.to_s.rjust(3, '0')}"
  end

  # atomic: tempfile → rename
  def sync
    data = load_json
    yield data
    write_json(data)
  end

  def load_json
    content = File.read(JSON_PATH)
    JSON.parse(content)
  rescue JSON::ParserError
    { "version" => 1, "reviews" => [] }
  end

  def write_json(data)
    dir = JSON_PATH.dirname
    FileUtils.mkdir_p(dir) unless dir.exist?

    tmp = Tempfile.new("reviews_", dir)
    tmp.write(JSON.pretty_generate(data))
    tmp.flush
    tmp.close
    FileUtils.mv(tmp.path, JSON_PATH)
  end

  def ensure_file!
    dir = JSON_PATH.dirname
    FileUtils.mkdir_p(dir) unless dir.exist?
    unless JSON_PATH.exist?
      File.write(JSON_PATH, JSON.pretty_generate({ "version" => 1, "reviews" => [] }))
    end
  end
end
