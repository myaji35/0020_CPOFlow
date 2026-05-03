# frozen_string_literal: true

# AUDIT-002: 미배정 Order 자동 담당자 배정 서비스
#
# 우선순위:
#   1. client.default_assignee_id
#   2. supplier.default_assignee_id
#   3. branch별 admin 첫 번째 user
#   4. nil (배정 안 함)
#
# ISS-309(PO 자동 인식)가 이 서비스를 활용 예정 → public API 안정적 유지
class AutoAssignerService
  # @param order [Order]
  def initialize(order)
    @order = order
  end

  # 담당자를 resolve하여 Assignment 레코드를 생성한다.
  # 이미 배정된 Order는 건너뜀.
  # @return [Integer, nil] 배정된 user_id, 배정 불가면 nil
  def call
    return nil if @order.assignments.exists?

    user_id = resolve_assignee
    return nil unless user_id

    Assignment.find_or_create_by!(order: @order, user_id: user_id) do |a|
      a.role = "auto"
    end
    user_id
  end

  private

  def resolve_assignee
    @order.client&.default_assignee_id ||
      @order.supplier&.default_assignee_id ||
      branch_default_assignee
  end

  def branch_default_assignee
    # Order에 branch 컬럼 없음 → creator(user)의 branch 기준으로 fallback
    branch = @order.user&.branch
    return nil if branch.blank?
    User.where(role: :admin, branch: branch).first&.id
  end
end
