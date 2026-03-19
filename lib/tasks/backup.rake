# frozen_string_literal: true

# SQLite3 DB 백업 Rake 태스크
# 사용법: bin/rails db:backup
# cron 설정: 0 2 * * * cd /rails && bin/rails db:backup RAILS_ENV=production
namespace :db do
  desc "SQLite3 데이터베이스 백업 (날짜별 파일명)"
  task backup: :environment do
    db_path = ActiveRecord::Base.connection_db_config.database
    backup_dir = Rails.root.join("storage", "backups")
    FileUtils.mkdir_p(backup_dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    backup_file = backup_dir.join("cpoflow_#{timestamp}.sqlite3")

    # SQLite online backup (WAL 모드에서도 안전)
    system("sqlite3 #{db_path} '.backup #{backup_file}'")

    if File.exist?(backup_file)
      size_mb = (File.size(backup_file) / 1024.0 / 1024.0).round(2)
      Rails.logger.info "[DB Backup] Created: #{backup_file} (#{size_mb} MB)"
      puts "Backup created: #{backup_file} (#{size_mb} MB)"

      # 30일 이전 백업 자동 삭제
      old_backups = Dir.glob(backup_dir.join("cpoflow_*.sqlite3")).select do |f|
        File.mtime(f) < 30.days.ago
      end
      old_backups.each { |f| File.delete(f) }
      puts "Cleaned up #{old_backups.count} old backups" if old_backups.any?
    else
      Rails.logger.error "[DB Backup] FAILED for #{db_path}"
      puts "Backup FAILED!"
    end
  end
end
