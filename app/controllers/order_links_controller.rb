class OrderLinksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_link, only: %i[confirm reject]

  def confirm
    @link.update!(status: "confirmed")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("suggestion-#{@link.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def reject
    @link.update!(status: "rejected")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("suggestion-#{@link.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def new
    @order = Order.find(params[:order_id])
    @relations = OrderLink::RELATIONS
    render layout: false
  end

  def create
    source = Order.find(params[:source_id])
    target_type = params[:target_type].presence_in(%w[Order OrderQuote]) || "Order"
    target = target_type.constantize.find(params[:target_id])
    @link = OrderLink.create!(
      source: source,
      target: target,
      relation: params[:relation],
      status: "confirmed",
      confidence: 1.0,
      created_by: current_user,
      metadata: { source: "manual", actor: current_user.email }
    )
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "drawer-panel-#{source.id}-flow-frame",
          %(<turbo-frame id="drawer-panel-#{source.id}-flow-frame" src="#{order_flow_path(source)}"></turbo-frame>).html_safe
        )
      end
      format.html { redirect_to order_path(source) }
    end
  end

  def search
    q = params[:q].to_s.strip
    @results = if q.present?
      Order.where("title LIKE ? OR reference_no LIKE ?", "%#{q}%", "%#{q}%").limit(10)
    else
      Order.none
    end
    render partial: "order_links/search_results", locals: { results: @results }
  end

  private

  def set_link
    @link = OrderLink.find(params[:id])
  end
end
