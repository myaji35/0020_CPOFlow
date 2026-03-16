# frozen_string_literal: true

# 납기 위험도 자동 계산 서비스
# 납기일, 현재 상태, 각 스테이지 평균 소요일을 기반으로 위험 점수(0-100)와 등급 산정
class RiskAssessmentService
  # 각 스테이지에서 다음으로 넘어가는 데 걸리는 평균 영업일
  STAGE_DAYS = {
    "new_rfq"        => 1,
    "make_quo"       => 3,
    "pending_po"     => 7,
    "new_po"         => 2,
    "delivery_items" => 14,
    "problem"        => 3,
    "get_grn"        => 0,
    "give_up"        => 0
  }.freeze

  STAGE_ORDER = %w[new_rfq make_quo pending_po new_po delivery_items problem get_grn give_up].freeze

  def self.calculate(order)
    new(order).calculate
  end

  def self.batch_update!
    updated = 0
    Order.where.not(status: [ :get_grn, :give_up ]).find_each do |order|
      result = calculate(order)
      order.update_columns(
        risk_score:      result[:score],
        risk_level:      result[:level],
        risk_updated_at: Time.current
      )
      updated += 1
    end
    # 납품 완료된 주문은 위험도 초기화
    Order.get_grn.where.not(risk_level: "none")
         .update_all(risk_score: 0, risk_level: "none", risk_updated_at: Time.current)
    updated
  end

  def initialize(order)
    @order = order
  end

  def calculate
    return { score: 0, level: "none" } if @order.due_date.nil? || @order.get_grn? || @order.give_up?

    days_left       = (@order.due_date - Date.today).to_i
    min_days_needed = minimum_days_needed

    score = compute_score(days_left, min_days_needed)
    level = score_to_level(score)

    { score: score, level: level }
  end

  private

  def stages_remaining
    current_idx = STAGE_ORDER.index(@order.status.to_s) || 0
    STAGE_ORDER[current_idx..]
  end

  def minimum_days_needed
    stages_remaining.sum { |s| STAGE_DAYS[s].to_i }
  end

  def compute_score(days_left, min_needed)
    if days_left < 0              then 100  # 이미 지연
    elsif days_left < min_needed  then 90   # 물리적으로 납기 불가
    elsif days_left <= 7          then 75
    elsif days_left <= 14         then 50
    elsif days_left <= 30         then 25
    else                               10
    end
  end

  def score_to_level(score)
    case score
    when 90..100 then "critical"
    when 75..89  then "high"
    when 50..74  then "medium"
    when 10..49  then "low"
    else              "none"
    end
  end
end
