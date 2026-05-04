namespace :users do
  desc "Employee 매칭 안 된 viewer 사용자 비활성화 (AtoZ 직원만 사용 정책)"
  task deactivate_unmatched: :environment do
    # admin/manager/member 권한자는 무조건 active 유지 (이미 검증된 직원)
    # viewer 중 Employee 매칭 안 된 사용자만 active=false 전환
    target = User.viewer.where(active: true).reject { |u| u.employee.present? }
    puts "비활성화 대상: #{target.size}명"
    target.each { |u| puts "  - #{u.email} (#{u.name})" }
    target.each { |u| u.update_column(:active, false) }
    puts "완료. 사용자에게 다음 로그인 시 /pending_approval 안내됩니다."
  end
end
