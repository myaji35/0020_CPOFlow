# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    results = []

    like = "%#{q}%"

    # ISS-227: 검색 대상 확장 — reference_no/rfq_no/po_no 포함
    # ISS-255: Branch 격리 — Order 는 scoped_orders 로 제한 (Client/Supplier/Employee/Project 는 공유 마스터)
    results += scoped_orders.where(
      "title LIKE ? OR customer_name LIKE ? OR original_email_subject LIKE ? OR " \
      "original_email_from LIKE ? OR reference_no LIKE ? OR rfq_no LIKE ? OR po_no LIKE ?",
      like, like, like, like, like, like, like
    ).limit(5).map do |o|
      sub_parts = [ Order::STATUS_LABELS[o.status] ]
      sub_parts << "RFQ##{o.reference_no}" if o.reference_no.present?
      { type: "order", id: o.id, icon: "clipboard", label: o.title.presence || o.original_email_subject,
        sub: sub_parts.compact.join(" · "), url: order_path(o) }
    end

    results += Client.where("name LIKE ? OR code LIKE ? OR ecount_code LIKE ?", like, like, like)
                     .limit(3).map do |c|
                       { type: "client", icon: "building", label: c.name,
                         sub: [ "발주처", c.country, c.ecount_code ].compact.reject(&:blank?).join(" · "),
                         url: client_path(c) }
                     end

    results += Supplier.where("name LIKE ? OR code LIKE ? OR ecount_code LIKE ?", like, like, like)
                       .limit(3).map do |s|
                         { type: "supplier", icon: "truck", label: s.name,
                           sub: [ "거래처", s.country, s.ecount_code ].compact.reject(&:blank?).join(" · "),
                           url: supplier_path(s) }
                       end

    results += Employee.where("name LIKE ? OR name_en LIKE ? OR passport_number LIKE ?", like, like, like)
                       .limit(3).map do |e|
                         { type: "employee", icon: "user", label: e.name,
                           sub: [ e.job_title, e.nationality ].compact.reject(&:blank?).join(" · "),
                           url: employee_path(e) }
                       end

    results += Project.where("name LIKE ? OR code LIKE ? OR location LIKE ?", like, like, like)
                      .limit(3).map do |p|
                        { type: "project", icon: "map-pin", label: p.name,
                          sub: [ "현장", p.site_category, p.location ].compact.reject(&:blank?).join(" · "),
                          url: project_path(p) }
                      end

    render json: results
  end
end
