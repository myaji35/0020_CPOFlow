# frozen_string_literal: true

require "test_helper"

class ReviewJsonSyncServiceTest < ActiveSupport::TestCase
  def setup
    # 각 테스트마다 임시 JSON 파일 경로를 사용
    @original_path = ReviewJsonSyncService::JSON_PATH
    @tmp_dir = Dir.mktmpdir("review_sync_test")
    @tmp_json = File.join(@tmp_dir, "reviews.json")

    # 상수 오버라이드 (테스트 격리)
    ReviewJsonSyncService.send(:remove_const, :JSON_PATH)
    ReviewJsonSyncService.const_set(:JSON_PATH, Pathname.new(@tmp_json))

    @service = ReviewJsonSyncService.new
    @review = Review.create!(
      rating: 4,
      body: "CSV 내보내기에 컬럼 셀렉터가 있으면 좋겠습니다. 감사 보고용 레포트에 필요합니다."
    )
  end

  def teardown
    # 상수 복원
    ReviewJsonSyncService.send(:remove_const, :JSON_PATH)
    ReviewJsonSyncService.const_set(:JSON_PATH, @original_path)
    FileUtils.rm_rf(@tmp_dir)
  end

  # --- append ---

  test "append — reviews.json에 리뷰 추가됨" do
    @service.append(@review)

    data = JSON.parse(File.read(@tmp_json))
    assert_equal 1, data["reviews"].size
    assert_equal "RV-#{@review.id.to_s.rjust(3, '0')}", data["reviews"].first["id"]
  end

  test "append — email 원문 미포함" do
    @review.update!(email: "secret@example.com")
    @service.append(@review)

    data = JSON.parse(File.read(@tmp_json))
    entry = data["reviews"].first
    assert_nil entry["email"], "JSON에 email 원문이 포함되면 안 됩니다"
  end

  test "append — 여러 리뷰 누적 가능" do
    review2 = Review.create!(rating: 3, body: "담당자별 감사 로그 필터가 필요합니다.")

    @service.append(@review)
    @service.append(review2)

    data = JSON.parse(File.read(@tmp_json))
    assert_equal 2, data["reviews"].size
  end

  test "append — 중복 ID 방지 (같은 리뷰 두번 append 시 1건만)" do
    @service.append(@review)
    @service.append(@review)  # 동일 리뷰 재append

    data = JSON.parse(File.read(@tmp_json))
    ids = data["reviews"].map { |r| r["id"] }
    assert_equal ids.uniq, ids, "중복 ID가 있습니다"
    assert_equal 1, data["reviews"].size
  end

  # --- update ---

  test "update — 기존 레코드 상태 변경 반영" do
    # acceptance (b): status transition 후 reviews.json 반영
    @service.append(@review)

    @review.status = "triaged"
    @review.save!
    @service.update(@review)

    data = JSON.parse(File.read(@tmp_json))
    review_id = "RV-#{@review.id.to_s.rjust(3, '0')}"
    entry = data["reviews"].find { |r| r["id"] == review_id }

    assert_not_nil entry, "업데이트된 리뷰를 JSON에서 찾을 수 없습니다"
    assert_equal "triaged", entry["status"]
  end

  test "update — JSON에 없는 리뷰도 append됨" do
    # JSON 파일에 없는 상태에서 update 호출
    @service.update(@review)

    data = JSON.parse(File.read(@tmp_json))
    assert_equal 1, data["reviews"].size
  end

  # --- 파일 없을 때 자동 생성 ---

  test "JSON 파일 없어도 서비스 초기화 성공" do
    FileUtils.rm_f(@tmp_json)
    assert_nothing_raised { ReviewJsonSyncService.new }
  end

  test "JSON 파일 없을 때 append 후 파일 생성됨" do
    FileUtils.rm_f(@tmp_json)
    service = ReviewJsonSyncService.new
    service.append(@review)

    assert File.exist?(@tmp_json), "reviews.json이 생성되어야 합니다"
  end

  # --- version 필드 ---

  test "version 필드가 1로 유지됨" do
    @service.append(@review)
    data = JSON.parse(File.read(@tmp_json))
    assert_equal 1, data["version"]
  end
end
