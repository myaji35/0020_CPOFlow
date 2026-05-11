# frozen_string_literal: true

# SQLite 성능 튜닝 (운영 DB 진단 2026-05-11 기반)
#
# 측정값: DB 125.7MB / orders 12K / activities 17K
# - 기본 cache_size=2000(8MB) → 디스크 I/O 빈번
# - temp_store=DEFAULT(disk) → ORDER BY temp file 디스크
#
# 모든 SQLite connection 체크아웃 시 PRAGMA 적용.
ActiveSupport.on_load(:active_record) do
  ActiveSupport::Notifications.subscribe("!connection.active_record") do |_, _, _, _, payload|
    conn = payload[:connection]
    next unless conn && conn.adapter_name.casecmp("SQLite").zero?
    begin
      conn.execute("PRAGMA cache_size = -50000")
      conn.execute("PRAGMA temp_store = MEMORY")
      conn.execute("PRAGMA mmap_size = 268435456")
    rescue StandardError => e
      Rails.logger.warn "[sqlite_perf] PRAGMA failed: #{e.message}"
    end
  end

  # 부트 시점 즉시 한 번 적용 (현재 연결)
  if ActiveRecord::Base.connected? && ActiveRecord::Base.connection.adapter_name.casecmp("SQLite").zero?
    begin
      ActiveRecord::Base.connection.execute("PRAGMA cache_size = -50000")
      ActiveRecord::Base.connection.execute("PRAGMA temp_store = MEMORY")
      ActiveRecord::Base.connection.execute("PRAGMA mmap_size = 268435456")
      Rails.logger.info "[sqlite_perf] applied at boot: cache_size=-50000 temp_store=MEMORY mmap_size=256MB"
    rescue StandardError => e
      Rails.logger.warn "[sqlite_perf] boot apply failed: #{e.message}"
    end
  end
end
