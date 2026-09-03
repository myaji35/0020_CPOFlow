# frozen_string_literal: true

require "test_helper"
require "rake"

class AgentRunsBackfillTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("agent_runs:backfill")
  end

  test "backfill imports all legacy records idempotently" do
    user = User.create!(email: "agent-run-#{SecureRandom.hex(4)}@example.com",
                        password: "Pass1234!", name: "Agent Run")
    order = Order.create!(title: "Agent run backfill test", customer_name: "Test", user: user)
    order.attachments.attach(
      io: StringIO.new("quote"), filename: "quote.txt", content_type: "text/plain"
    )
    attachment = order.attachments.first

    rule_only = ClassificationLog.create!(
      classifier_version: "v2", model: "rule-only", reason: "matched rule",
      cost_usd: 0, latency_ms: 5, order: order
    )
    haiku = ClassificationLog.create!(
      classifier_version: "v2", model: "haiku-4.5",
      reason: "stage3_fallback_to_stage2: unavailable", cost_usd: 0,
      latency_ms: 10, order: order
    )
    attachment_analysis = AttachmentQuoteAnalysis.create!(
      order: order, active_storage_attachment: attachment, status: "completed"
    )
    rfq_analysis = RfqAutoAnalysis.create!(order: order, user: user, status: "failed")

    task = Rake::Task["agent_runs:backfill"]
    2.times do
      task.reenable
      task.invoke
    end

    source_ids = [ rule_only.id, haiku.id, attachment_analysis.id, rfq_analysis.id ]
    assert_equal 4, AgentRun.where(source_id: source_ids).count
    assert_nil AgentRun.find_by!(source_type: "ClassificationLog", source_id: rule_only.id).cost_usd
    refute_nil AgentRun.find_by!(source_type: "ClassificationLog", source_id: haiku.id).cost_usd
    assert_equal "fallback", AgentRun.find_by!(source_type: "ClassificationLog", source_id: haiku.id).status
  end
end
