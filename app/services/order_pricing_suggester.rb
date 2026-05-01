# frozen_string_literal: true

# ISS-308: make_quo 견적 단가 자동 추천 + 공급사 추천
#
# OrderQuote 이력에서 같은 품목의 최근 단가를 반환하고,
# 해당 품목을 과거에 발주한 공급사 목록을 제안한다.
#
# 매칭 전략 (우선순위):
#   1. 같은 client_id + 같은 품목명 (가장 정확)
#   2. 같은 품목명 전체 (client 무관)
#   3. 품목명 LIKE 매칭 (앞 단어만 입력된 경우)
class OrderPricingSuggester
  RECENT_LIMIT = 5

  def self.call(order)
    new(order).call
  end

  def initialize(order)
    @order = order
    @item  = order.item_name.to_s.strip
    @client_id = order.client_id
  end

  def call
    return empty_result if @item.blank?

    quotes  = fetch_recent_quotes
    suppliers = fetch_suggested_suppliers

    suggested = quotes.first

    {
      suggested_unit_price: suggested&.unit_price,
      suggested_currency:   suggested&.currency || "AED",
      recent_quotes: quotes.map { |q| quote_hash(q) },
      suggested_suppliers: suppliers
    }
  end

  private

  # OrderQuote 이력 조회
  # 1) client + 정확 품목명 → 2) 정확 품목명 → 3) LIKE 품목명
  def fetch_recent_quotes
    base = OrderQuote.joins(:order, :supplier)
                     .where.not(unit_price: nil)
                     .order(created_at: :desc)

    item_lower = @item.downcase

    # 전략 1: client + 정확 매칭
    if @client_id.present?
      exact_with_client = base.where(orders: { client_id: @client_id })
                              .where("LOWER(orders.item_name) = ?", item_lower)
                              .limit(RECENT_LIMIT)
      return exact_with_client.to_a if exact_with_client.count >= 3
    end

    # 전략 2: 정확 매칭 (client 무관)
    exact = base.where("LOWER(orders.item_name) = ?", item_lower)
                .limit(RECENT_LIMIT)
    return exact.to_a if exact.any?

    # 전략 3: LIKE 매칭 (부분 입력)
    like_pattern = "#{item_lower}%"
    base.where("LOWER(orders.item_name) LIKE ?", like_pattern)
        .limit(RECENT_LIMIT)
        .to_a
  end

  # 공급사 추천: OrderQuote 이력 → Order.supplier 이력 순
  def fetch_suggested_suppliers
    item_lower = @item.downcase

    # 1) OrderQuote의 supplier (견적을 넣은 공급사)
    quote_supplier_ids = OrderQuote.joins(:order)
                                   .where("LOWER(orders.item_name) = ?", item_lower)
                                   .group(:supplier_id)
                                   .order(Arel.sql("COUNT(*) DESC"))
                                   .limit(RECENT_LIMIT)
                                   .pluck(:supplier_id)

    # 2) Order.supplier_id 이력 (실제 발주한 공급사)
    order_supplier_ids = Order.where("LOWER(item_name) = ?", item_lower)
                              .where.not(supplier_id: nil)
                              .group(:supplier_id)
                              .order(Arel.sql("COUNT(*) DESC"))
                              .limit(RECENT_LIMIT)
                              .pluck(:supplier_id)

    # 합치되 중복 제거 + 순서 유지 (quote 이력 우선)
    combined_ids = (quote_supplier_ids + order_supplier_ids).uniq.first(RECENT_LIMIT)
    return [] if combined_ids.empty?

    Supplier.where(id: combined_ids, active: true)
            .index_by(&:id)
            .values_at(*combined_ids)
            .compact
            .map { |s| { id: s.id, name: s.name, code: s.ecount_code } }
  end

  def quote_hash(q)
    {
      date:        q.created_at.to_date.to_s,
      unit_price:  q.unit_price,
      currency:    q.currency || "AED",
      supplier_id: q.supplier_id,
      supplier:    q.supplier&.name,
      order_id:    q.order_id,
      item_name:   q.order.item_name
    }
  end

  def empty_result
    { suggested_unit_price: nil, suggested_currency: "AED", recent_quotes: [], suggested_suppliers: [] }
  end
end
