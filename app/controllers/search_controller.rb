# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    results = []

    results += Order.where("title LIKE ? OR customer_name LIKE ?", "%#{q}%", "%#{q}%")
                    .limit(5).map do |o|
                      { type: "order", id: o.id, icon: "clipboard", label: o.title,
                        sub: Order::STATUS_LABELS[o.status], url: order_path(o) }
                    end

    results += Client.where("name LIKE ?", "%#{q}%")
                     .limit(3).map do |c|
                       { type: "client", icon: "building", label: c.name,
                         sub: "발주처", url: client_path(c) }
                     end

    results += Supplier.where("name LIKE ?", "%#{q}%")
                       .limit(3).map do |s|
                         { type: "supplier", icon: "truck", label: s.name,
                           sub: "거래처", url: supplier_path(s) }
                       end

    results += Employee.where("name LIKE ? OR name_en LIKE ?", "%#{q}%", "%#{q}%")
                       .limit(3).map do |e|
                         { type: "employee", icon: "user", label: e.name,
                           sub: e.job_title, url: employee_path(e) }
                       end

    results += Project.where("name LIKE ?", "%#{q}%")
                      .limit(3).map do |p|
                        { type: "project", icon: "map-pin", label: p.name,
                          sub: "현장", url: project_path(p) }
                      end

    render json: results
  end
end
