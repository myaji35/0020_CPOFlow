# frozen_string_literal: true

namespace :employee do
  desc "Employee.unmapped 자동 매핑 — 이름 정확 매치 + 이메일 매치 (DRY_RUN=1 미리보기)"
  task auto_link_users: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    puts dry_run ? "=== DRY-RUN 모드 ===" : "=== 실행 모드 ==="
    puts ""

    matched = 0
    skipped = 0

    Employee.unmapped.find_each do |emp|
      # 1순위: email 매치 (있을 때만)
      user = User.find_by("LOWER(email) = ?", emp.email.downcase) if emp.email.present?

      # 2순위: 이름 정확 매치
      user ||= begin
        name_field = emp.respond_to?(:name_en) && emp.name_en.present? ? emp.name_en : emp.name
        User.find_by(name: name_field) if name_field.present?
      end

      if user
        if dry_run
          puts "  [DRY] Employee##{emp.id} '#{emp.name}' → User##{user.id} (#{user.email})"
        else
          emp.update_column(:user_id, user.id)
          puts "  Employee##{emp.id} '#{emp.name}' → User##{user.id}"
        end
        matched += 1
      else
        puts "  [SKIP] Employee##{emp.id} '#{emp.name}' (email=#{emp.email.inspect}) — 매칭 없음"
        skipped += 1
      end
    end

    puts ""
    puts "결과: 매칭 #{matched}건 / 스킵 #{skipped}건"
    puts "남은 unmapped: #{Employee.unmapped.count}건"
  end
end
