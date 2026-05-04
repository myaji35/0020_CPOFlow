namespace :users do
  desc "Employee 매칭된 viewer를 일괄 member로 승격 (이메일 매칭 = 직원 인증)"
  task promote_matched_viewers: :environment do
    # admin은 그대로 유지. 매칭된 viewer만 member로 승격.
    target = User.viewer.joins("INNER JOIN employees ON employees.user_id = users.id")
    puts "승격 대상: #{target.count}명"
    target.each do |u|
      u.update_column(:role, User.roles[:member])
      puts "  ✓ #{u.email} (#{u.employee&.name}) viewer → member"
    end
    puts "완료."
  end
end
