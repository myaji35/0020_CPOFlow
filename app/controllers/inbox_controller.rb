class InboxController < ApplicationController
  def index
    base_scope = Order.where.not(original_email_from: [ nil, "" ])
                      .includes(:user, :assignees, :client, :supplier, :project)

    # Filter support: all (default), rfq (inbox only), converted (non-inbox)
    @current_filter = params[:filter].presence || "all"
    case @current_filter
    when "rfq"
      base_scope = base_scope.where(status: :inbox)
    when "converted"
      base_scope = base_scope.where.not(status: :inbox)
    end

    # Search support
    @search_query = params[:q].to_s.strip
    if @search_query.present?
      search_term = "%#{@search_query}%"
      base_scope = base_scope.where(
        "original_email_subject LIKE :q OR original_email_from LIKE :q OR customer_name LIKE :q OR title LIKE :q",
        q: search_term
      )
    end

    @all_orders = base_scope.order(created_at: :desc).limit(100)

    # Counts for sidebar badges (unfiltered, unsearched)
    email_scope = Order.where.not(original_email_from: [ nil, "" ])
    @count_all       = email_scope.count
    @count_rfq       = email_scope.where(status: :inbox).count
    @count_converted = email_scope.where.not(status: :inbox).count
  end

  def show
    @order = Order.find_by(source_email_id: params[:id]) ||
             Order.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to inbox_path, alert: "해당 이메일을 찾을 수 없습니다."
  end

  def convert_to_order
    @order = Order.find(params[:id])
    if @order.update(status: :reviewing)
      Activity.create!(order: @order, user: current_user, action: "moved_to_kanban")
      redirect_to kanban_path, notice: t("inbox.convert_success")
    else
      redirect_back fallback_location: inbox_path, alert: "Failed to convert."
    end
  end

  # Manual sync trigger (called from Inbox UI "Sync" button)
  def sync
    accounts = current_user.email_accounts.where(connected: true)
    if accounts.any?
      accounts.each { |acc| EmailSyncJob.perform_later(account_id: acc.id) }
      render json: { status: "ok", message: "Sync queued for #{accounts.count} account(s)" }
    else
      render json: { status: "error", message: "No connected accounts" }, status: :unprocessable_entity
    end
  end
end
