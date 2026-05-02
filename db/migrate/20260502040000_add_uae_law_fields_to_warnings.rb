# ISS-332+: UAE Federal Decree-Law No. 33 of 2021 (Articles 39, 41, 44) 반영
# 법적 절차 추적 + 외국인 근로자 비자/추방 연계 필드
class AddUaeLawFieldsToWarnings < ActiveRecord::Migration[8.1]
  def change
    add_column :warnings, :notified_at,        :datetime  # Art.41 — 서면 통지 일시 (필수)
    add_column :warnings, :employee_response,  :text       # 직원 진술 (Art.41)
    add_column :warnings, :response_received_at, :datetime # 진술 접수 일시
    add_column :warnings, :mohre_reportable,   :boolean,   default: false, null: false
    add_column :warnings, :mohre_reported_at,  :datetime
    add_column :warnings, :wage_deduction_days, :integer   # Art.39 — 월 5일 이내 임금 감액
    add_column :warnings, :suspension_days,     :integer   # Art.39 — 최대 14일 정직
    add_column :warnings, :gross_misconduct,    :boolean,  default: false, null: false  # Art.44 즉시 해고
    add_column :warnings, :article_reference,   :string    # Art.39, Art.44 등 인용
    add_column :warnings, :visa_action_required, :boolean, default: false, null: false  # 비자 취소 필요 여부

    add_index :warnings, :gross_misconduct
    add_index :warnings, :mohre_reportable
  end
end
