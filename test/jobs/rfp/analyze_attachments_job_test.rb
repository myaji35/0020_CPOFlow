# frozen_string_literal: true

require "test_helper"

module Rfp
  class AnalyzeAttachmentsJobTest < ActiveJob::TestCase
    setup do
      @user = User.create!(email: "rfp-job-#{SecureRandom.hex(4)}@x.com", password: "Pass1234!", name: "RFP")
      @order = Order.create!(reference_no: "RFP-#{SecureRandom.hex(3)}", title: "T", user: @user, customer_name: "CN")
      @order.attachments.attach(io: StringIO.new("item specification text"), filename: "rfq.txt", content_type: "text/plain")
      @result = {
        "items" => [ { "name" => "Valve", "quantity" => 2, "unit" => "EA",
                       "source_excerpt" => "Valve specification line" } ],
        "_model" => Rfp::ItemExtractor::DEFAULT_MODEL,
        "_cost_usd" => 0.0123, "_input_tokens" => 123, "_output_tokens" => 45
      }
    end

    test "creates parent and item extraction child with usage" do
      perform_with_service_stubs

      parent = AgentRun.where(agent_name: "rfp.analyze_attachments", order_id: @order.id).last
      child = AgentRun.where(agent_name: "rfp.item_extract", order_id: @order.id).last
      assert_equal "success", parent.status
      assert_equal parent.id, child.parent_run_id
      assert_equal 0.0123, child.cost_usd.to_f
      assert_equal 123, child.input_tokens
      assert_equal 1, @order.tasks.count
    end

    test "agent run create failure does not prevent task creation" do
      with_stubbed_class_method(AgentRun, :create!, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
        perform_with_service_stubs
      end

      assert_equal 1, @order.tasks.count
      assert_equal "done", @order.reload.rfp_analysis_state
    end

    private

    def perform_with_service_stubs
      extraction_result = @result
      with_stubbed_class_method(Rfp::AttachmentRelevanceFilter, :call, ->(*) { { relevant: true } }) do
        with_stubbed_class_method(Rfp::AttachmentExtractor, :call, ->(*) { { filename: "rfq.txt", text: "item specification text" } }) do
          with_stubbed_class_method(Rfp::ItemExtractor, :call, ->(*) { extraction_result }) do
            with_stubbed_class_method(Rfp::SummaryReportService, :call, ->(*) { nil }) do
              Rfp::AnalyzeAttachmentsJob.perform_now(@order.id)
            end
          end
        end
      end
    end

    def with_stubbed_class_method(klass, method_name, replacement)
      original = klass.method(method_name)
      klass.define_singleton_method(method_name, replacement)
      yield
    ensure
      klass.define_singleton_method(method_name, original)
    end
  end
end
