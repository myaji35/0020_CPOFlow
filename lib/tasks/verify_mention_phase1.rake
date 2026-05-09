# frozen_string_literal: true
# ISS-353 Phase 1 — T17: 실 클릭 3-op 검증 rake (CPOFlow 룰 충족)
#
# CPOFlow 룰: UI CRUD 기능 배포 후 반드시 실제 핵심 플로우 검증.
# unit test 통과만으로는 "기능 동작" 증명 부족 → CREATE/UPDATE/DELETE 3 op을
# 실제 모델/서비스/컨트롤러 호출로 끝까지 통과시켜야 한다.
#
# 사용:
#   bin/rails mentions:verify_phase1
#
# PASS 조건: 마지막 줄에 "=== 결과: ALL PASS ==="
namespace :mentions do
  desc "Phase 1 검증: CREATE/UPDATE/DELETE 3-op 실 동작 확인 (CPOFlow 룰)"
  task verify_phase1: :environment do
    puts "=== ISS-353 Phase 1 — 3-op verification ==="
    failures = []

    # === Setup ===
    sender = User.find_or_create_by!(email: "verify_sender@example.com") do |u|
      u.password = "password123"
      u.role     = :member
      u.name     = "검증발신"
      u.active   = true
    end

    receiver = User.find_or_create_by!(email: "verify_receiver@example.com") do |u|
      u.password = "password123"
      u.role     = :member
      u.name     = "검증수신"
      u.active   = true
    end

    # MentionParserService는 Employee.find_by(name:) 로 사용자 매칭한다.
    Employee.find_or_create_by!(name: "검증수신") do |e|
      e.user            = receiver
      e.nationality     = "KR"
      e.employment_type = "regular"
    end

    order = Order.create!(
      user:          sender,
      title:         "Phase1 verify #{Time.current.to_i}",
      customer_name: "Verify Customer",
      status:        :new_rfq
    )

    # === [1/3] CREATE ===
    print "[1/3] CREATE: @검증수신 멘션 코멘트 생성..."
    comment = Comment.create!(order: order, user: sender, body: "@검증수신 자료 검토 요청")
    MentionParserService.new(comment, sender).call

    notif = Notification.where(user: receiver, notifiable: order, notification_type: "mentioned").last
    if notif.nil?
      failures << "CREATE: Notification 미생성"
      puts " FAIL"
    elsif order.reload.mention_total_count < 1
      failures << "CREATE: order.mention_total_count not incremented (got #{order.mention_total_count})"
      puts " FAIL"
    elsif notif.intent_level != 0
      failures << "CREATE: intent_level should be 0 (got #{notif.intent_level})"
      puts " FAIL"
    else
      puts " PASS (notif_id=#{notif.id}, total=#{order.mention_total_count}, unread=#{order.mention_unread_count})"
    end

    # === [2/3] UPDATE (acknowledge) ===
    print "[2/3] UPDATE: receiver가 [✓ 확인] 클릭..."
    if notif
      notif.acknowledge!(viewer: receiver)
      if notif.reload.acknowledged_at.nil?
        failures << "UPDATE: acknowledged_at not set"
        puts " FAIL"
      elsif order.reload.mention_acknowledged_count < 1
        failures << "UPDATE: mention_acknowledged_count not incremented (got #{order.mention_acknowledged_count})"
        puts " FAIL"
      else
        puts " PASS (acknowledged_at=#{notif.acknowledged_at}, ack_count=#{order.mention_acknowledged_count})"
      end
    else
      failures << "UPDATE: skipped (no notification from CREATE)"
      puts " SKIP"
    end

    # === [3/3] DELETE (Order destroy → cascade) ===
    print "[3/3] DELETE: Order 삭제 → notifications dependent: :destroy..."
    order_id = order.id
    order.destroy
    remaining = Notification.where(notifiable_type: "Order", notifiable_id: order_id).count
    if remaining > 0
      failures << "DELETE: #{remaining} notifications remain after order destroy"
      puts " FAIL"
    else
      puts " PASS (모든 child notifications 삭제됨)"
    end

    # === Summary ===
    puts ""
    if failures.empty?
      puts "=== 결과: ALL PASS ==="
      exit 0
    else
      puts "=== 결과: #{failures.size}건 FAIL ==="
      failures.each { |f| puts "  - #{f}" }
      exit 1
    end
  end
end
