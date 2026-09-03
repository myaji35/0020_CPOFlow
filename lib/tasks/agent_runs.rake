# frozen_string_literal: true

namespace :agent_runs do
  desc "Backfill agent_runs from legacy analysis tables"
  task backfill: :environment do
    backfill = lambda do |model, scope, agent_name, &mapper|
      inserted = 0
      skipped = 0

      scope.in_batches(of: 1000) do |relation|
        records = relation.to_a
        source_ids = records.map(&:id)
        existing_ids = AgentRun.where(source_type: model.name, source_id: source_ids).pluck(:source_id)
        rows = records.reject { |record| existing_ids.include?(record.id) }.map(&mapper)
        skipped += records.size - rows.size

        unless rows.empty?
          before_ids = AgentRun.where(source_type: model.name, source_id: source_ids).pluck(:source_id)
          begin
            AgentRun.insert_all(rows, unique_by: [ :source_type, :source_id ])
          rescue StandardError => e
            Rails.logger.warn "[AgentRun] write failed agent=#{agent_name} #{e.class}: #{e.message.to_s.first(200)}"
          end
          after_ids = AgentRun.where(source_type: model.name, source_id: source_ids).pluck(:source_id)
          inserted += (after_ids - before_ids).size
          skipped += rows.size - (after_ids - before_ids).size
        end
      end

      puts "#{model.name}: inserted=#{inserted} skipped=#{skipped}"
    end

    now = Time.current
    backfill.call(ClassificationLog, ClassificationLog.all, "gmail.classify") do |log|
      reason = log.reason.to_s
      status = if reason.start_with?("stage3_fallback_to_stage2", "credit_exhausted", "stage2_failed")
        "fallback"
      elsif reason.start_with?("safety_fallback")
        "failure"
      else
        "success"
      end

      {
        source_type: ClassificationLog.name,
        source_id: log.id,
        agent_name: "gmail.classify",
        kind: "service",
        status: status,
        order_id: log.order_id,
        started_at: log.created_at - (log.latency_ms.to_i / 1000.0),
        finished_at: log.created_at,
        duration_ms: log.latency_ms,
        model: log.model,
        cost_usd: log.model.to_s.start_with?("rule-only") ? nil : log.cost_usd,
        meta: {
          verdict: log.verdict,
          stage_reached: log.stage_reached,
          reason: log.reason,
          confidence: log.confidence,
          would_exclude: log.would_exclude,
          cache_hit: log.cache_hit
        }.to_json,
        created_at: now,
        updated_at: now
      }
    end

    [
      [ AttachmentQuoteAnalysis, "quote.attachment_analyze" ],
      [ RfqAutoAnalysis, "rfq_auto.analyze" ]
    ].each do |model, agent_name|
      backfill.call(model, model.where(status: %w[completed failed]), agent_name) do |analysis|
        {
          source_type: model.name,
          source_id: analysis.id,
          agent_name: agent_name,
          kind: "job",
          status: analysis.status == "completed" ? "success" : "failure",
          order_id: analysis.order_id,
          started_at: analysis.started_at || analysis.created_at,
          finished_at: analysis.completed_at,
          duration_ms: analysis.latency_ms,
          model: analysis.llm_model,
          cost_usd: analysis.cost_usd,
          error_message: analysis.error_message,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
