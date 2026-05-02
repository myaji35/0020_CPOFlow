class CalendarController < ApplicationController
  def index
    @view = %w[monthly weekly].include?(params[:view]) ? params[:view] : "monthly"
    @month = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    today  = Date.today

    grid_start = nil
    grid_end   = nil
    if @view == "weekly"
      @week_start = params[:date] ? Date.parse(params[:date]).beginning_of_week(:sunday) : today.beginning_of_week(:sunday)
      @week_end   = @week_start + 6.days
      @orders = Order.where(due_date: @week_start..@week_end)
                     .includes(:assignees, :client, :project, :card_status)
                     .by_due_date
    else
      first_day  = @month.beginning_of_month
      grid_start = first_day - first_day.wday.days
      grid_end   = grid_start + 41.days
      @orders = Order.where(due_date: grid_start..grid_end)
                     .includes(:assignees, :client, :project, :card_status)
                     .by_due_date
    end

    # 통계: 이번 달 기준
    month_start = @month.beginning_of_month
    month_end   = @month.end_of_month
    month_orders = @orders.select { |o| o.due_date >= month_start && o.due_date <= month_end }
    @stats = {
      total:     month_orders.count,
      overdue:   month_orders.count { |o| o.due_date < today && !o.done? },
      this_week: month_orders.count { |o| o.due_date >= today.beginning_of_week(:sunday) && o.due_date <= today.end_of_week(:sunday) },
      completed: month_orders.count { |o| o.done? || o.get_grn? }
    }

    # ISS-208: 통합 이벤트 소스 (납기 / 비자 만료 / 계약 만료 / 휴가)
    # 기본은 전체 활성. params[:sources] (쉼표 구분) 지원
    @event_sources = (params[:sources].to_s.split(",") & %w[orders visas contracts leaves]).presence ||
                     %w[orders visas contracts leaves]

    range_start = (@view == "weekly") ? @week_start : grid_start
    range_end   = (@view == "weekly") ? @week_end   : grid_end

    @calendar_events = []
    if @event_sources.include?("orders")
      # @orders는 이미 로드됨 — 재활용
      @orders.each do |o|
        @calendar_events << {
          type: "order",
          date: o.due_date,
          title: o.title.presence || "주문 ##{o.id}",
          path: order_path(o),
          object: o
        }
      end
    end
    if @event_sources.include?("visas") && defined?(Visa)
      Visa.where(expiry_date: range_start..range_end, status: "active")
          .includes(:employee).each do |v|
        @calendar_events << {
          type: "visa",
          date: v.expiry_date,
          title: "비자 만료: #{v.employee&.name} (#{v.visa_type})",
          path: employee_path(v.employee),
          object: v
        }
      end
    end
    if @event_sources.include?("contracts") && defined?(EmploymentContract)
      EmploymentContract.where(end_date: range_start..range_end)
                        .includes(:employee).each do |c|
        @calendar_events << {
          type: "contract",
          date: c.end_date,
          title: "계약 만료: #{c.employee&.name}",
          path: employee_path(c.employee),
          object: c
        }
      end
    end
    # ISS-305: 승인된 휴가를 캘린더에 통합 (기간 표시 — 시작일로 그룹)
    if @event_sources.include?("leaves") && defined?(Leave)
      Leave.approved.for_calendar(range_start, range_end)
           .includes(:employee).each do |lv|
        (lv.start_date..lv.end_date).each do |day|
          next unless day >= range_start && day <= range_end
          @calendar_events << {
            type: "leave",
            date: day,
            title: "휴가: #{lv.employee&.name} (#{lv.leave_type_label})",
            path: leave_path(lv),
            object: lv
          }
        end
      end
    end

    # 날짜별 그룹 + 타입별 카운트
    @events_by_date = @calendar_events.group_by { |e| e[:date].to_date }
    @type_counts    = @calendar_events.group_by { |e| e[:type] }.transform_values(&:size)
  end
end
