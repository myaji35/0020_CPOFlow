# frozen_string_literal: true

# SQLite3 동시접속 최적화 — WAL 모드 + busy_timeout
# WAL(Write-Ahead Logging): 읽기와 쓰기가 동시에 가능 (기본 모드는 읽기/쓰기 상호 배제)
# busy_timeout: 다른 트랜잭션이 잠금 중일 때 최대 5초 대기 후 재시도
if ActiveRecord::Base.connection.adapter_name == "SQLite"
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
  ActiveRecord::Base.connection.execute("PRAGMA busy_timeout=5000")
  ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
  ActiveRecord::Base.connection.execute("PRAGMA cache_size=-20000")
end
