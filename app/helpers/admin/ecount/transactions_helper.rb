# frozen_string_literal: true

module Admin
  module Ecount
    module TransactionsHelper
      TRANSACTION_STATUS_COLORS = {
        "new_rfq"        => { bg: "#EBF5FF", text: "#1E3A5F", border: "#B3D4FC" },
        "make_quo"       => { bg: "#FFF8E1", text: "#7B6100", border: "#FFD54F" },
        "pending_po"     => { bg: "#FFF3E0", text: "#E65100", border: "#FFB74D" },
        "new_po"         => { bg: "#E8F5E9", text: "#1B5E20", border: "#81C784" },
        "delivery_items" => { bg: "#E3F2FD", text: "#0D47A1", border: "#64B5F6" },
        "problem"        => { bg: "#FFEBEE", text: "#B71C1C", border: "#EF9A9A" },
        "get_grn"        => { bg: "#E0F2F1", text: "#004D40", border: "#80CBC4" },
        "give_up"        => { bg: "#F3E5F5", text: "#4A148C", border: "#CE93D8" },
        "done"           => { bg: "#E8F5E9", text: "#1E8E3E", border: "#66BB6A" }
      }.freeze

      TRANSACTION_STATUS_LABELS = {
        "new_rfq" => "New RFQ", "make_quo" => "Make QUO", "pending_po" => "Pending PO",
        "new_po" => "New PO", "delivery_items" => "Delivery", "problem" => "Problem",
        "get_grn" => "Get GRN", "give_up" => "Give Up", "done" => "Done"
      }.freeze

      def tx_filter_params(overrides = {})
        { q: params[:q], status: params[:status], client_id: params[:client_id],
          supplier_id: params[:supplier_id], period: params[:period],
          sort: @sort_col, dir: @sort_dir }.compact_blank.merge(overrides)
      end

      def tx_sort_link(label, col)
        new_dir = (@sort_col == col.to_s && @sort_dir == :asc) ? "desc" : "asc"
        arrow = if @sort_col == col.to_s
                  @sort_dir == :asc ? " ↑" : " ↓"
        else
                  ""
        end
        link_to "#{label}#{arrow}".html_safe,
                admin_ecount_transactions_path(tx_filter_params(sort: col, dir: new_dir, page: 1)),
                class: "hover:text-[#00A1E0] #{'text-[#00A1E0] font-bold' if @sort_col == col.to_s}"
      end

      def tx_fmt_amount(val)
        return "-" if val.blank? || val.to_f.zero?
        number_to_currency(val, unit: "", precision: 0, delimiter: ",")
      end

      def tx_status_color(status)
        TRANSACTION_STATUS_COLORS[status] || { bg: "#F5F5F5", text: "#616161", border: "#E0E0E0" }
      end

      def tx_status_label(status)
        TRANSACTION_STATUS_LABELS[status] || status.to_s.humanize
      end
    end
  end
end
