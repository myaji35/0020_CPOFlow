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

  # ISS-057 — Plan §8 Day 3 자동 중단 게이트
  #
  # Shadow Mode 운영 3일차에 자동 실행. 4가지 임계값 검증:
  #   1) 일 평균 비용 > $0.35 → FAIL
  #   2) Sonnet 에스컬레이션 비율 > 50% → FAIL
  #   3) v1(사용자 액션) ↔ v2 불일치율 > 10% → FAIL
  #   4) safety_fallback 비율 > 5% → FAIL
  #
  # Usage:
  #   bin/rails classify_v2:day3_check
  #
  # 성공 시 tmp/classify_v2_day3_status.json 갱신 (status=passed).
  # 실패 시 동일 파일에 status=failed + 실패 사유 기록 + exit 1.
  desc "Day 3 Shadow Mode 자동 중단 게이트 — 비용/Sonnet비율/불일치/에러율 검증"
  task day3_check: :environment do
    require "json"
    require "fileutils"

    result = ClassifyV2Day3Gate.new.run

    status_path = Rails.root.join("tmp/classify_v2_day3_status.json")
    FileUtils.mkdir_p(status_path.dirname)
    File.write(status_path, JSON.pretty_generate(result))

    if result[:status] == "passed"
      puts "✓ Day 3 gate PASSED"
      result[:checks].each do |c|
        puts "  ✓ #{c[:name]}: actual=#{c[:actual]} threshold=#{c[:threshold]}"
      end
    else
      Rails.logger.error "[classify_v2:day3_check] FAILED: #{result[:failures].map { |f| f[:name] }.join(', ')}"
      puts "✗ Day 3 gate FAILED"
      result[:failures].each do |f|
        puts "  ✗ #{f[:name]}: actual=#{f[:actual]} threshold=#{f[:threshold]}"
        puts "      reason: #{f[:reason]}"
      end
      exit 1
    end
  end

  def pct(num, total)
    return "0.0%" if total.zero?

    "#{'%.1f' % (num.to_f / total * 100)}%"
  end

  # ISS-059: 과거 v1 Order에 Stage 1 RuleGate backfill
  #
  # 대표님 요청 (2026-04-09): 배포 후 신규 메일만 v2 배지가 뜨는데,
  # 과거 누적 12,651건도 AI 배지로 볼 수 있게 해달라.
  #
  # 이 task는 classifier_version='v1' 인 모든 Order를 대상으로 Stage 1 RuleGate 만
  # 재실행하여 다음 필드를 채운다:
  #   - classifier_version       → 'v2'
  #   - stage_reached            → 0 (stage0 hit) 또는 1 (stage1 결과)
  #   - classification_confidence→ pass_to_llm/whitelist_fast=0.5 (unknown 진짜 verdict), reject_no_signal=0.95
  #   - cache_hit                → false
  #
  # **Freeze 규칙 절대 준수**: rfq_status 는 건드리지 않음.
  #
  # ClassificationLog 도 audit 목적으로 insert.
  #
  # Stage 2/3 (LLM) 은 호출하지 않으므로 비용 $0.
  #
  # Usage:
  #   bin/rails classify_v2:backfill_past_orders                # 전체
  #   bin/rails classify_v2:backfill_past_orders[1000]          # 1000건만
  #   bin/rails classify_v2:backfill_past_orders[0,dry]         # dry-run (쓰기 없음)
  desc "과거 v1 Order에 Stage 1 RuleGate backfill (Freeze 규칙 준수, rfq_status 건드리지 않음)"
  task :backfill_past_orders, [ :limit, :mode ] => :environment do |_t, args|
    limit = args[:limit].to_i
    dry   = args[:mode].to_s == "dry"

    puts "=" * 72
    puts "[classify_v2:backfill_past_orders]"
    puts "  limit: #{limit.zero? ? 'ALL' : limit}"
    puts "  mode:  #{dry ? 'DRY-RUN (no writes)' : 'WRITE'}"
    puts "=" * 72

    scope = Order.where(classifier_version: "v1")
    scope = scope.limit(limit) if limit.positive?
    total = scope.count
    puts "  대상: #{total}건"
    puts

    if total.zero?
      puts "✓ 대상 Order 없음 — 모든 Order가 이미 v2"
      exit 0
    end

    stats = Hash.new(0)
    t0 = Time.now

    scope.find_each(batch_size: 500) do |order|
      stats[:total] += 1

      email_hash = {
        id:       "backfill_order_#{order.id}",
        message_id: order.source_email_id || "backfill_order_#{order.id}",
        subject:  order.original_email_subject.to_s,
        from:     order.original_email_from.to_s,
        body:     order.original_email_body.to_s
      }

      # --- Stage 0: Ariba/자사/noise 조기 제외 (RfqDetectorService 재사용) ---
      #
      # confidence 규칙 — Inbox 뷰 배지 매핑에 맞춘다:
      #   >= 0.85 → 파란 "AI: 견적성"
      #   0.60~0.85 → 노란 "AI: 모호"
      #   < 0.60 → 회색 "AI: 제외 권장"
      # 따라서 excluded verdict 는 0.40 (회색), confirmed 는 0.95 (파란),
      # uncertain(Stage 2 미호출) 은 0.60 (노란) 으로 매핑.
      detector = Gmail::RfqDetectorService.new(email_hash)
      stage_reached, confidence, verdict, reason, model =
        if detector.send(:ariba_sender?)
          [ 0, 0.95, :confirmed, "stage0_ariba_sender", "rule-only" ]
        elsif detector.send(:own_sender?)
          [ 0, 0.40, :excluded, "stage0_own_sender", "rule-only" ]
        elsif detector.send(:excluded_sender?) || detector.send(:excluded_subject?)
          [ 0, 0.40, :excluded, "stage0_excluded_pattern", "rule-only" ]
        else
          gate = Gmail::Stage1::RuleGate.decide(email_hash)
          case gate.action
          when :reject_no_signal
            [ 1, 0.40, :excluded, "stage1_#{gate.reason}", "rule-only" ]
          when :whitelist_fast, :pass_to_llm
            # Stage 2 호출 안 함 — unknown verdict. 중간 confidence 0.60 → "AI: 모호" 배지
            [ 1, 0.60, :uncertain, "stage1_#{gate.reason}_pending_llm", "rule-only" ]
          else
            [ 1, 0.0, :uncertain, "stage1_unknown", "rule-only" ]
          end
        end

      stats[verdict] += 1
      stats[:"stage#{stage_reached}"] += 1

      unless dry
        # **Freeze 규칙 준수**: rfq_status 는 건드리지 않음. v2 메트릭 필드만 update.
        order.update_columns(
          classifier_version: "v2",
          stage_reached: stage_reached,
          classification_confidence: confidence,
          cache_hit: false
        )

        # Audit log
        begin
          ClassificationLog.create!(
            order_id: order.id,
            email_message_id: email_hash[:message_id],
            classifier_version: "v2",
            stage_reached: stage_reached,
            verdict: verdict.to_s,
            is_rfq: verdict == :confirmed,
            confidence: confidence,
            would_exclude: verdict == :excluded,
            reason: "backfill:#{reason}",
            cost_usd: 0.0,
            latency_ms: 0,
            cache_hit: false,
            model: model
          )
        rescue StandardError => e
          Rails.logger.warn "[backfill] log insert failed for Order##{order.id}: #{e.message}"
        end
      end

      if (stats[:total] % 1000).zero?
        elapsed = (Time.now - t0).round(1)
        puts "  ... 진행: #{stats[:total]}/#{total} (#{elapsed}s)"
      end
    end

    elapsed = (Time.now - t0).round(1)

    puts
    puts "=" * 72
    puts "📊 결과 (#{elapsed}s)"
    puts "=" * 72
    puts "  총 처리: #{stats[:total]}건"
    puts
    puts "  Stage 분포:"
    puts "    Stage 0 (Ariba/자사/noise): #{stats[:stage0]}건 (#{pct(stats[:stage0], stats[:total])})"
    puts "    Stage 1 (RuleGate):         #{stats[:stage1]}건 (#{pct(stats[:stage1], stats[:total])})"
    puts
    puts "  verdict 분포:"
    puts "    confirmed:  #{stats[:confirmed]}건 (#{pct(stats[:confirmed], stats[:total])}) → \"AI: 견적성\" 배지 (파란)"
    puts "    excluded:   #{stats[:excluded]}건 (#{pct(stats[:excluded], stats[:total])}) → \"AI: 제외 권장\" 배지 (회색)"
    puts "    uncertain:  #{stats[:uncertain]}건 (#{pct(stats[:uncertain], stats[:total])}) → \"AI: 모호\" 배지 (노란, Stage 2 미호출)"
    puts
    puts "  Freeze 규칙 준수: rfq_status 는 0건 변경 (Plan §4.5)"
    puts "  LLM 비용: $0.00 (Stage 2/3 미호출)"
    puts "=" * 72
  end
end
