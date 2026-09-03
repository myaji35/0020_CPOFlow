# frozen_string_literal: true

# 에이전트 실행의 상태, 지연 시간, 토큰 및 비용을 기록한다.
# 기록 실패가 실제 업무 흐름에 영향을 주지 않도록 모든 DB 쓰기는 best-effort로 처리한다.
class AgentRun < ApplicationRecord
  belongs_to :order, optional: true
  belongs_to :parent_run, class_name: "AgentRun", optional: true
  has_many :child_runs, class_name: "AgentRun", foreign_key: :parent_run_id, dependent: :nullify

  validates :agent_name, :kind, :status, presence: true

  scope :in_window, ->(from) { where("started_at >= ?", from) }
  scope :for_agent, ->(name) { where(agent_name: name) }
  scope :failed,    -> { where(status: %w[failure fallback]) }
  scope :roots,     -> { where(parent_run_id: nil) }

  class << self
    def track(agent:, kind: "service", order: nil, parent: nil, source: nil)
      run = start!(agent: agent, kind: kind, order: order, parent: parent, source: source)
      result = yield run
      run.finish!(status: "success")
      result
    rescue StandardError => e
      run&.fail!(e)
      raise
    end

    def start!(agent:, kind:, order:, parent:, source:)
      create!(
        agent_name: agent,
        kind: kind,
        status: "running",
        started_at: Time.current,
        order: order,
        parent_run: parent,
        source_type: source&.class&.base_class&.name,
        source_id: source&.id
      )
    rescue StandardError => e
      log_write_failure(agent, e)
      NullRun.new
    end

    private

    def log_write_failure(agent_name, error)
      Rails.logger.warn "[AgentRun] write failed agent=#{agent_name} #{error.class}: #{error.message.to_s.first(200)}"
    end
  end

  def note(model: nil, cost_usd: nil, input_tokens: nil, output_tokens: nil, cache_read_tokens: nil, meta: nil)
    pending_notes[:model] = model unless model.nil?
    pending_notes[:cost_usd] = cost_usd unless cost_usd.nil?
    pending_notes[:input_tokens] = input_tokens unless input_tokens.nil?
    pending_notes[:output_tokens] = output_tokens unless output_tokens.nil?
    pending_notes[:cache_read_tokens] = cache_read_tokens unless cache_read_tokens.nil?
    pending_notes[:meta] = meta.to_json.first(4096) unless meta.nil?
    self
  end

  def finish!(status: "success", **attrs)
    finished = Time.current
    elapsed_ms = ((finished - started_at) * 1000).to_i
    update!(pending_notes.merge(attrs).merge(status: status, finished_at: finished, duration_ms: elapsed_ms))
    self
  rescue StandardError => e
    log_write_failure(e)
    self
  end

  def fail!(error_or_message, status: "failure")
    message = if error_or_message.is_a?(Exception)
      "#{error_or_message.class}: #{error_or_message.message}"
    else
      error_or_message.to_s
    end
    finish!(status: status, error_message: message.first(1000))
  end

  private

  def pending_notes
    @pending_notes ||= {}
  end

  def log_write_failure(error)
    Rails.logger.warn "[AgentRun] write failed agent=#{agent_name} #{error.class}: #{error.message.to_s.first(200)}"
  end

  class NullRun
    def note(...)
      self
    end

    def finish!(...)
      self
    end

    def fail!(...)
      self
    end

    def persisted?
      false
    end
  end
end
