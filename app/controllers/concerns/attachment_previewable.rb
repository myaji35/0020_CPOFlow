# frozen_string_literal: true

# 첨부파일 미리보기 공통 로직 — InboxController, OrdersController 공용
module AttachmentPreviewable
  extend ActiveSupport::Concern

  private

  def preview_blob(blob)
    content_type = blob.content_type.to_s

    if content_type.include?("spreadsheet") || content_type.include?("excel") ||
       blob.filename.to_s.match?(/\.xlsx?\z/i)
      blob.open do |tempfile|
        spreadsheet = Roo::Spreadsheet.open(tempfile.path, extension: File.extname(blob.filename.to_s))
        html = build_excel_preview_html(spreadsheet, blob.filename.to_s)
        render html: html.html_safe, layout: false
      end
    elsif content_type.include?("html")
      blob.open do |tempfile|
        html_content = File.read(tempfile.path, encoding: "UTF-8")
        esc_script = '<script>document.addEventListener("keydown",function(e){if(e.key==="Escape")window.parent.postMessage("close-preview-modal","*")});</script>'
        html_content = html_content.sub("</body>", "#{esc_script}</body>")
        render html: html_content.html_safe, layout: false
      end
    elsif content_type.include?("pdf") || content_type.start_with?("image/")
      redirect_to rails_blob_path(blob, disposition: "inline"), allow_other_host: false
    else
      redirect_to rails_blob_path(blob, disposition: "attachment"), allow_other_host: false
    end
  end

  def build_excel_preview_html(spreadsheet, filename)
    sheets_html = spreadsheet.sheets.map.with_index do |sheet_name, idx|
      spreadsheet.default_sheet = sheet_name
      first_row = spreadsheet.first_row
      last_row  = [ spreadsheet.last_row || 0, 500 ].min
      first_col = spreadsheet.first_column
      last_col  = spreadsheet.last_column

      next "" unless first_row && last_row && first_col && last_col

      rows_html = (first_row..last_row).map do |row|
        cells = (first_col..last_col).map do |col|
          val = spreadsheet.cell(row, col)
          tag = row == first_row ? "th" : "td"
          "<#{tag}>#{ERB::Util.html_escape(val.to_s)}</#{tag}>"
        end.join
        "<tr>#{cells}</tr>"
      end.join

      tab_id = "sheet-#{idx}"
      <<~HTML
        <div class="sheet-tab" data-sheet="#{tab_id}" style="display:#{idx == 0 ? 'block' : 'none'}">
          <div style="overflow-x:auto;">
            <table>#{rows_html}</table>
          </div>
        </div>
      HTML
    end.join

    tab_buttons = spreadsheet.sheets.map.with_index do |name, idx|
      active = idx == 0 ? "active" : ""
      "<button class='tab-btn #{active}' onclick='switchSheet(#{idx})'>#{ERB::Util.html_escape(name)}</button>"
    end.join

    <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><title>#{ERB::Util.html_escape(filename)}</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #fff; color: #1f2937; }
        .toolbar { position: sticky; top: 0; z-index: 10; background: #f8fafc; border-bottom: 1px solid #e2e8f0;
                   padding: 8px 16px; display: flex; align-items: center; justify-content: space-between; }
        .toolbar h1 { font-size: 13px; font-weight: 600; color: #334155; }
        .tabs { display: flex; gap: 2px; padding: 0 16px; background: #f1f5f9; border-bottom: 1px solid #e2e8f0; }
        .tab-btn { padding: 6px 14px; font-size: 12px; border: none; background: transparent; color: #64748b;
                   cursor: pointer; border-bottom: 2px solid transparent; }
        .tab-btn.active { color: #0369a1; border-bottom-color: #0369a1; font-weight: 600; background: #fff; }
        .tab-btn:hover { background: #e2e8f0; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; }
        th, td { border: 1px solid #e2e8f0; padding: 4px 8px; text-align: left; white-space: nowrap; max-width: 300px; overflow: hidden; text-overflow: ellipsis; }
        th { background: #f1f5f9; font-weight: 600; color: #334155; position: sticky; top: 0; }
        tr:hover td { background: #f0f9ff; }
        tr:nth-child(even) td { background: #f8fafc; }
        tr:hover td, tr:nth-child(even):hover td { background: #e0f2fe; }
      </style>
      </head><body>
        <div class="toolbar">
          <h1>#{ERB::Util.html_escape(filename)}</h1>
        </div>
        #{"<div class='tabs'>#{tab_buttons}</div>" if spreadsheet.sheets.size > 1}
        #{sheets_html}
        <script>
          function switchSheet(idx) {
            document.querySelectorAll('.sheet-tab').forEach((el, i) => { el.style.display = i === idx ? 'block' : 'none'; });
            document.querySelectorAll('.tab-btn').forEach((el, i) => { el.classList.toggle('active', i === idx); });
          }
          document.addEventListener('keydown', function(e) { if (e.key === 'Escape') window.parent.postMessage('close-preview-modal', '*'); });
        </script>
      </body></html>
    HTML
  end
end
