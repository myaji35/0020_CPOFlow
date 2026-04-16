# frozen_string_literal: true

namespace :employees do
  desc "Employee-User 자동 연결 (DRY_RUN=1 미리보기, CONFIRM_GUESS=1 추측 매핑도 적용)"
  task link_users: :environment do
    dry_run = ENV.fetch("DRY_RUN", "0") == "1"
    confirm_guess = ENV.fetch("CONFIRM_GUESS", "0") == "1"
    puts dry_run ? "=== DRY-RUN 모드 ===" : "=== 실행 모드 ==="
    puts "CONFIRM_GUESS=#{confirm_guess}" unless dry_run
    puts ""

    # ── 수동 매핑 (Production 데이터 기준) ──
    # { employee_name => { email:, confidence: :sure/:guess } }
    manual_map = {
      "KANG"     => { email: "kss@atozone.com",      confidence: :sure,  note: "강승식 대표" },
      "ALEC"     => { email: "sales@atoz2010.com",    confidence: :sure,  note: "Sales 담당 (Seles)" },
      "Cristina" => { email: "admin@atozone.com",     confidence: :sure,  note: "Account/Admin" },
      "LALA"     => { email: "ahmed@atozone.com",     confidence: :guess, note: "추측: Ahmed 팀?" },
      "RAJAN"    => { email: "park@atozone.com",      confidence: :guess, note: "추측: Park 팀?" },
      "Renjith"  => { email: "sarah@atozone.com",     confidence: :guess, note: "추측: Sarah 팀?" },
      "NICKA"    => { email: "admin@cpoflow.com",     confidence: :guess, note: "추측: CPOFlow Admin?" },
    }

    employees = Employee.where(user_id: nil)
    users_by_email = User.all.index_by { |u| u.email.downcase }
    users_by_name = User.where.not(name: [nil, ""]).index_by { |u| u.name.downcase.strip }
    already_assigned_user_ids = Employee.where.not(user_id: nil).pluck(:user_id)

    linked = 0
    skipped = 0
    guessed = 0

    employees.find_each do |emp|
      user = nil
      match_reason = nil
      confidence = :auto

      # Strategy 1: 수동 매핑 테이블
      if (mapping = manual_map[emp.name])
        user = users_by_email[mapping[:email].downcase]
        confidence = mapping[:confidence]
        match_reason = "#{confidence == :sure ? '확정' : '추측'}매핑(#{mapping[:email]}) — #{mapping[:note]}"
      end

      # Strategy 2: name_en <-> User.name 정확 일치
      if user.nil? && emp.name_en.present?
        user = users_by_name[emp.name_en.downcase.strip]
        match_reason = "name_en=user.name" if user
      end

      # Strategy 3: Employee.name <-> User.name 정확 일치
      if user.nil?
        user = users_by_name[emp.name.downcase.strip]
        match_reason = "name=user.name" if user
      end

      # Strategy 4: email prefix <-> name parameterize
      if user.nil?
        slug = emp.name.parameterize(separator: "")
        slug_en = emp.name_en.present? ? emp.name_en.parameterize(separator: "") : nil
        User.all.each do |u|
          prefix = u.email.split("@").first.downcase.gsub(/[^a-z0-9]/, "")
          if prefix == slug || (slug_en && prefix == slug_en)
            user = u
            match_reason = "email_prefix(#{prefix})"
            break
          end
        end
      end

      # 이미 다른 Employee에 할당된 User는 스킵
      if user && already_assigned_user_ids.include?(user.id)
        puts "[CONFLICT] EMP##{emp.id} #{emp.name} → USER##{user.id} #{user.email} 이미 다른 Employee에 연결됨"
        skipped += 1
        next
      end

      if user
        skip_this = (confidence == :guess && !confirm_guess && !dry_run)

        if dry_run
          tag = confidence == :guess ? "DRY-GUESS" : "DRY"
          puts "[#{tag}] EMP##{emp.id} #{emp.name} (#{emp.name_en}) → USER##{user.id} #{user.email} (#{user.name}) [#{match_reason}]"
          guessed += 1 if confidence == :guess
        elsif skip_this
          puts "[GUESS-SKIP] EMP##{emp.id} #{emp.name} — 추측 매핑 건너뜀 (CONFIRM_GUESS=1 로 적용)"
          guessed += 1
          next
        else
          emp.update!(user_id: user.id)
          already_assigned_user_ids << user.id
          tag = confidence == :guess ? "OK-GUESS" : "OK"
          puts "[#{tag}]  EMP##{emp.id} #{emp.name} → USER##{user.id} #{user.email} [#{match_reason}]"
        end
        linked += 1
      else
        puts "[SKIP] EMP##{emp.id} #{emp.name} (#{emp.name_en}) — 매칭 실패"
        skipped += 1
      end
    end

    puts ""
    puts "결과: 연결 #{linked}건, 추측 #{guessed}건, 스킵 #{skipped}건"
    unless dry_run
      total = Employee.where.not(user_id: nil).count
      active = Employee.where(active: true).where.not(user_id: nil).count
      puts "현재 연결된 Employee: 전체 #{total}건, active #{active}건"
    end
    puts ""

    remaining = Employee.where(user_id: nil)
    if remaining.any?
      puts "미연결 직원 수동 연결 명령:"
      remaining.each do |emp|
        puts "  Employee.find(#{emp.id}).update!(user_id: <USER_ID>)  # #{emp.name} (#{emp.name_en})"
      end
      puts ""
      puts "사용 가능한 User:"
      used = Employee.where.not(user_id: nil).pluck(:user_id)
      User.where.not(id: used).each do |u|
        puts "  USER##{u.id}: #{u.email} (#{u.name})"
      end
    end
  end
end
