# frozen_string_literal: true

# ISS-045 Phase A 검증용 Backtest Rake Tasks
#
# 배포된 프로덕션 DB에 이미 저장된 Order(원본 이메일) 데이터를 가상 이메일로
# 변환하여 Stage 1 RuleGate를 실행. Gmail API 재호출 0건, LLM 비용 0원.
# 사용자의 실제 액션(rfq_status)을 정답지로 삼아 Recall/Precision 산출.
#
# Usage:
#   bin/rails classify_v2:backtest_stage1              # 전체 backtest
#   bin/rails classify_v2:backtest_stage1[1000]        # 1000건 샘플
#   bin/rails classify_v2:backtest_stage1[0,kepco]     # KEPCO 도메인만
#   bin/rails classify_v2:golden_collect               # Golden Dataset YAML 추출
#
# 정답지 매핑 (사용자 실제 액션):
#   rfq_status = rfq_triage  → 사용자가 견적으로 이동 → "confirmed"
#   rfq_status = rfq_excluded → 사용자가 삭제           → "excluded"
#   rfq_status = rfq_pending  → 아직 판정 전            → "unlabeled" (제외)

namespace :classify_v2 do
  desc "Stage 1 RuleGate backtest — Order 데이터로 Recall/Precision 산출"
  task :backtest_stage1, [ :limit, :domain_filter ] => :environment do |_t, args|
    limit  = args[:limit].to_i
    domain = args[:domain_filter].to_s.presence

    puts "=" * 72
    puts "[classify_v2:backtest_stage1]"
    puts "  limit:        #{limit.zero? ? 'ALL' : limit}"
    puts "  domain:       #{domain || 'ALL'}"
    puts "=" * 72

    scope = Order.where.not(original_email_subject: nil)
                 .where.not(rfq_status: nil)
                 .where(rfq_status: [
                   Order.rfq_statuses[:rfq_triage],
                   Order.rfq_statuses[:rfq_excluded]
                 ])

    scope = scope.where("original_email_from LIKE ?", "%#{domain}%") if domain
    scope = scope.limit(limit) if limit.positive?

    total = scope.count
    puts "  대상 Order 수: #{total}건 (rfq_triage/excluded만, pending 제외)"
    puts

    if total.zero?
      puts "⚠️  labeled Order가 없습니다. 사용자가 bulk_to_kanban / bulk_delete 액션을"
      puts "   수행해서 rfq_triage/rfq_excluded 상태로 만든 데이터가 필요합니다."
      exit 0
    end

    stats = {
      total:          0,
      tp:             0,  # RuleGate pass + rfq_triage (맞음)
      fp:             0,  # RuleGate pass + rfq_excluded (오탐)
      tn:             0,  # RuleGate reject + rfq_excluded (맞음)
      fn:             0,  # 🚨 RuleGate reject + rfq_triage (놓침)
      whitelist_fast: 0,
      strong_keyword: 0,
      weak_signal:    0,
      rejected:       0
    }
    fn_samples = []  # False Negative 샘플 (최대 10건)

    scope.find_each(batch_size: 500) do |order|
      stats[:total] += 1

      email_hash = {
        subject: order.original_email_subject.to_s,
        from:    order.original_email_from.to_s,
        body:    order.original_email_body.to_s
      }

      result = Gmail::Stage1::RuleGate.decide(email_hash)
      user_verdict = order.rfq_status == "rfq_triage" ? :confirmed : :excluded

      # Reason stat
      case result.reason
      when "whitelist_domain" then stats[:whitelist_fast] += 1
      when "strong_keyword"   then stats[:strong_keyword] += 1
      when "weak_signal"      then stats[:weak_signal]    += 1
      when "no_rfq_signal"    then stats[:rejected]       += 1
      end

      # Confusion matrix
      if result.pass? && user_verdict == :confirmed
        stats[:tp] += 1
      elsif result.pass? && user_verdict == :excluded
        stats[:fp] += 1
      elsif result.reject? && user_verdict == :excluded
        stats[:tn] += 1
      elsif result.reject? && user_verdict == :confirmed
        stats[:fn] += 1
        if fn_samples.size < 10
          fn_samples << {
            id:      order.id,
            subject: order.original_email_subject.to_s[0, 80],
            from:    order.original_email_from.to_s[0, 50]
          }
        end
      end

      if (stats[:total] % 1000).zero?
        puts "  ... 진행: #{stats[:total]}/#{total}"
      end
    end

    puts
    puts "=" * 72
    puts "📊 결과"
    puts "=" * 72
    puts "  총 판정: #{stats[:total]}건"
    puts
    puts "  Stage 분기 통계 (LLM 호출 필요 여부):"
    puts "    whitelist_fast : #{stats[:whitelist_fast]}건 (#{pct(stats[:whitelist_fast], stats[:total])})  → Stage 2 진입"
    puts "    strong_keyword : #{stats[:strong_keyword]}건 (#{pct(stats[:strong_keyword], stats[:total])})  → Stage 2 진입"
    puts "    weak_signal    : #{stats[:weak_signal]}건 (#{pct(stats[:weak_signal], stats[:total])})  → Stage 2 진입"
    puts "    rejected       : #{stats[:rejected]}건 (#{pct(stats[:rejected], stats[:total])})  → LLM 호출 불필요"
    puts
    llm_needed = stats[:whitelist_fast] + stats[:strong_keyword] + stats[:weak_signal]
    savings = stats[:rejected].to_f / stats[:total] * 100.0
    puts "  💰 LLM 호출 절감: #{llm_needed}건만 Stage 2 필요 (#{'%.1f' % savings}% 절감)"
    puts

    puts "  Confusion Matrix (vs 사용자 정답):"
    puts "                 │ Pass(LLM) │ Reject(no LLM) │"
    puts "    confirmed    │ #{stats[:tp].to_s.rjust(7)} ✓ │ #{stats[:fn].to_s.rjust(10)} ✗│  ← FN (놓침)"
    puts "    excluded     │ #{stats[:fp].to_s.rjust(7)} ? │ #{stats[:tn].to_s.rjust(10)} ✓│"
    puts

    # Recall for Stage 1 gate = "사용자가 confirmed한 것 중 Stage 1이 pass 시킨 비율"
    recall      = stats[:tp].to_f / [ stats[:tp] + stats[:fn], 1 ].max
    specificity = stats[:tn].to_f / [ stats[:tn] + stats[:fp], 1 ].max
    puts "  🎯 Recall (confirmed 중 pass 비율)   : #{'%.2f%%' % (recall * 100)} (목표 99.5%)"
    puts "  🎯 Specificity (excluded 중 reject) : #{'%.2f%%' % (specificity * 100)} (높을수록 Stage 2 비용 절감)"
    puts

    if stats[:fn].positive?
      puts "🚨 False Negative (Stage 1이 놓친 견적 메일) 샘플:"
      fn_samples.each_with_index do |fn, i|
        puts "    #{(i + 1).to_s.rjust(2)}. [##{fn[:id]}] #{fn[:subject]}"
        puts "        from: #{fn[:from]}"
      end
      puts
      puts "  💡 조치: 위 발신자 도메인을 WHITELIST_DOMAINS에 추가하거나"
      puts "          본문 키워드를 WEAK_SIGNALS에 추가하여 커버리지 개선."
    else
      puts "✅ False Negative 0건 — Stage 1이 labeled 견적 메일을 모두 pass 시켰습니다."
    end
    puts "=" * 72
  end

  desc "Stage 1 분류 분포 — labeled 없이 전수 Order에 RuleGate 적용하여 분포만 측정"
  task :distribution, [ :limit ] => :environment do |_t, args|
    limit = args[:limit].to_i

    puts "=" * 72
    puts "[classify_v2:distribution]"
    puts "  목적: labeled 정답지 없이 Stage 1이 전수 Order를 어떻게 분류하는지 분포 측정"
    puts "  대상: 모든 Order (rfq_status 무관)"
    puts "  limit: #{limit.zero? ? 'ALL' : limit}"
    puts "=" * 72

    scope = Order.where.not(original_email_subject: nil)
    scope = scope.limit(limit) if limit.positive?
    total = scope.count
    puts "  총 대상: #{total}건"
    puts

    stats = Hash.new(0)
    by_domain = Hash.new { |h, k| h[k] = Hash.new(0) }
    sample_rejected = []
    sample_whitelist = []
    sample_strong = []

    scope.find_each(batch_size: 500) do |order|
      stats[:total] += 1

      email_hash = {
        subject: order.original_email_subject.to_s,
        from:    order.original_email_from.to_s,
        body:    order.original_email_body.to_s
      }
      result = Gmail::Stage1::RuleGate.decide(email_hash)

      stats[result.reason.to_sym] += 1
      stats[result.action] += 1

      # 도메인별 누적
      domain = order.original_email_from.to_s.match(/@([^>\s]+)/)&.[](1)&.downcase.to_s
      by_domain[domain][:total] += 1
      by_domain[domain][result.action] += 1

      # 샘플 수집
      if result.reason == "no_rfq_signal" && sample_rejected.size < 5
        sample_rejected << { id: order.id, subject: order.original_email_subject.to_s[0, 60],
                              from: order.original_email_from.to_s[0, 40] }
      elsif result.reason == "whitelist_domain" && sample_whitelist.size < 5
        sample_whitelist << { id: order.id, subject: order.original_email_subject.to_s[0, 60],
                               from: order.original_email_from.to_s[0, 40] }
      elsif result.reason == "strong_keyword" && sample_strong.size < 5
        sample_strong << { id: order.id, subject: order.original_email_subject.to_s[0, 60],
                            from: order.original_email_from.to_s[0, 40] }
      end

      puts "  ... 진행: #{stats[:total]}/#{total}" if (stats[:total] % 2000).zero?
    end

    puts
    puts "=" * 72
    puts "📊 Stage 1 분류 분포 결과"
    puts "=" * 72
    puts "  총 판정: #{stats[:total]}건"
    puts
    puts "  [LLM 호출 필요 — Stage 2로 진입]"
    puts "    whitelist_fast : #{stats[:whitelist_domain].to_s.rjust(6)}건 (#{pct(stats[:whitelist_domain], stats[:total])})"
    puts "    strong_keyword : #{stats[:strong_keyword].to_s.rjust(6)}건 (#{pct(stats[:strong_keyword], stats[:total])})"
    puts "    weak_signal    : #{stats[:weak_signal].to_s.rjust(6)}건 (#{pct(stats[:weak_signal], stats[:total])})"
    llm_needed = stats[:whitelist_domain] + stats[:strong_keyword] + stats[:weak_signal]
    puts "    ─────────────────────"
    puts "    소계           : #{llm_needed.to_s.rjust(6)}건 (#{pct(llm_needed, stats[:total])})"
    puts
    puts "  [LLM 호출 불필요 — Stage 1에서 rejected]"
    puts "    no_rfq_signal  : #{stats[:no_rfq_signal].to_s.rjust(6)}건 (#{pct(stats[:no_rfq_signal], stats[:total])})"
    puts

    # 비용 시뮬레이션
    haiku_cost = llm_needed * 0.0013  # Haiku 호출 평균 $0.0013
    sonnet_esc = (llm_needed * 0.30).to_i  # 30% 가정 (Plan v1.2)
    sonnet_cost = sonnet_esc * 0.0083
    total_cost = haiku_cost + sonnet_cost
    puts "  💰 LLM 비용 시뮬레이션 (전수 기준):"
    puts "    Haiku  : #{llm_needed}건 × $0.0013 = $#{'%.2f' % haiku_cost}"
    puts "    Sonnet : ~#{sonnet_esc}건 × $0.0083 = $#{'%.2f' % sonnet_cost} (30% 에스컬레이션 가정)"
    puts "    총합   : $#{'%.2f' % total_cost}"
    puts "    → 일일 평균 (400통/일 환산): $#{'%.3f' % (total_cost / (stats[:total] / 400.0))}"
    puts

    puts "  [샘플: whitelist_fast (whitelist 도메인 히트)]"
    sample_whitelist.each_with_index do |s, i|
      puts "    #{i + 1}. [##{s[:id]}] #{s[:subject]}"
      puts "        from: #{s[:from]}"
    end
    puts
    puts "  [샘플: strong_keyword (RFQ/견적요청 등)]"
    sample_strong.each_with_index do |s, i|
      puts "    #{i + 1}. [##{s[:id]}] #{s[:subject]}"
      puts "        from: #{s[:from]}"
    end
    puts
    puts "  [샘플: rejected (LLM 호출 없이 excluded)]"
    sample_rejected.each_with_index do |s, i|
      puts "    #{i + 1}. [##{s[:id]}] #{s[:subject]}"
      puts "        from: #{s[:from]}"
    end
    puts

    puts "  [도메인 상위 10 (전체 메일 수 기준)]"
    by_domain.sort_by { |_, v| -v[:total] }.first(10).each do |domain, counts|
      wl = counts[:whitelist_fast] || 0
      pass = (counts[:whitelist_fast] || 0) + (counts[:pass_to_llm] || 0)
      reject = counts[:reject_no_signal] || 0
      puts "    #{domain.ljust(35)} : #{counts[:total].to_s.rjust(5)}건  pass=#{pass}  reject=#{reject}  whitelist=#{wl}"
    end
    puts "=" * 72
  end

  desc "Golden Dataset 자동 추출 (Order 테이블 → test/fixtures/files/golden_dataset YAML)"
  task golden_collect: :environment do
    require "yaml"
    require "fileutils"

    out_dir = Rails.root.join("test/fixtures/files/golden_dataset")
    FileUtils.mkdir_p(out_dir.join("confirmed"))
    FileUtils.mkdir_p(out_dir.join("excluded"))

    confirmed = Order.where(rfq_status: :rfq_triage)
                     .where.not(original_email_subject: nil)
                     .where("created_at >= ?", 180.days.ago)
                     .order("RANDOM()")
                     .limit(100)
    excluded = Order.where(rfq_status: :rfq_excluded)
                    .where.not(original_email_subject: nil)
                    .where("created_at >= ?", 180.days.ago)
                    .order("RANDOM()")
                    .limit(100)

    puts "Golden Dataset 추출"
    puts "  confirmed: #{confirmed.count}건"
    puts "  excluded : #{excluded.count}건"

    [ [ confirmed, "confirmed" ], [ excluded, "excluded" ] ].each do |orders, label|
      orders.each_with_index do |order, idx|
        file = out_dir.join(label, "#{(idx + 1).to_s.rjust(3, '0')}.yml")
        data = {
          "id"                => order.id,
          "gmail_message_id"  => order.gmail_message_id,
          "subject"           => order.original_email_subject.to_s,
          "from"              => order.original_email_from.to_s,
          "body"              => order.original_email_body.to_s.first(8000),
          "expected_verdict"  => label,
          "customer_name"     => order.customer_name,
          "labeled_at"        => Time.current.iso8601
        }
        File.write(file, data.to_yaml)
      end
    end

    total = Dir[out_dir.join("**/*.yml")].size
    puts "✅ 완료: #{total}개 YAML 파일 저장 → #{out_dir}"
  end

  def pct(num, total)
    return "0.0%" if total.zero?

    "#{'%.1f' % (num.to_f / total * 100)}%"
  end
end
