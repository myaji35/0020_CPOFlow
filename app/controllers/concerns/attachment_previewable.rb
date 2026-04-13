# frozen_string_literal: true

# 첨부파일 미리보기 공통 로직 — InboxController, OrdersController 공용
module AttachmentPreviewable
  extend ActiveSupport::Concern

  private

  def preview_blob(blob)
    content_type = blob.content_type.to_s
    filename = blob.filename.to_s

    if content_type.include?("spreadsheet") || content_type.include?("excel") ||
       filename.match?(/\.xlsx?\z/i)
      # Excel → HTML 테이블 변환 (Roo gem)
      blob.open do |tempfile|
        spreadsheet = Roo::Spreadsheet.open(tempfile.path, extension: File.extname(filename))
        html = build_excel_preview_html(spreadsheet, filename)
        render html: html.html_safe, layout: false
      end
    elsif filename.match?(/\.csv\z/i)
      # CSV → HTML 테이블 변환
      blob.open do |tempfile|
        html = build_csv_preview_html(tempfile.path, filename)
        render html: html.html_safe, layout: false
      end
    elsif content_type.include?("html")
      # XSS 방어: HTML 첨부파일은 sandbox iframe 내에서 렌더링
      blob.open do |tempfile|
        html_content = File.read(tempfile.path, encoding: "UTF-8")
        sanitized = Rails::HTML5::SafeListSanitizer.new.sanitize(
          html_content,
          tags: %w[html head body meta title style div span p a b i u em strong br hr h1 h2 h3 h4 h5 h6
                   table thead tbody tfoot tr th td caption col colgroup
                   ul ol li dl dt dd pre code blockquote img figure figcaption
                   header footer nav section article aside main address],
          attributes: %w[class id style href src alt title width height colspan rowspan
                         align valign border cellpadding cellspacing target rel]
        )
        esc_script = '<script>document.addEventListener("keydown",function(e){if(e.key==="Escape")window.parent.postMessage("close-preview-modal","*")});</script>'
        sanitized = sanitized + esc_script
        render html: sanitized.html_safe, layout: false
      end
    elsif content_type.include?("pdf") || content_type.start_with?("image/")
      # PDF, 이미지 → 브라우저 inline 표시
      redirect_to rails_blob_path(blob, disposition: "inline"), allow_other_host: false
    elsif content_type.start_with?("text/") || filename.match?(/\.(txt|log|md|json|xml|yml|yaml)\z/i)
      # 텍스트 파일 → 코드 뷰어 스타일로 표시
      blob.open do |tempfile|
        html = build_text_preview_html(tempfile.path, filename)
        render html: html.html_safe, layout: false
      end
    else
      redirect_to rails_blob_path(blob, disposition: "attachment"), allow_other_host: false
    end
  end

  # CSV 파일 → HTML 테이블 미리보기
  def build_csv_preview_html(filepath, filename)
    require "csv"
    rows = CSV.read(filepath, encoding: "UTF-8:UTF-8", liberal_parsing: true).first(500)
    return build_text_preview_html(filepath, filename) if rows.empty?

    header = rows.first
    body_rows = rows.drop(1)

    header_html = header.map { |h| "<th>#{ERB::Util.html_escape(h.to_s)}</th>" }.join
    rows_html = body_rows.map do |row|
      cells = row.map { |c| "<td>#{ERB::Util.html_escape(c.to_s)}</td>" }.join
      "<tr>#{cells}</tr>"
    end.join

    <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><title>#{ERB::Util.html_escape(filename)}</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #fff; }
        .toolbar { position: sticky; top: 0; z-index: 10; background: #f8fafc; border-bottom: 1px solid #e2e8f0;
                   padding: 8px 16px; display: flex; align-items: center; gap: 8px; }
        .toolbar h1 { font-size: 13px; font-weight: 600; color: #334155; }
        .badge { font-size: 11px; color: #64748b; background: #e2e8f0; padding: 2px 8px; border-radius: 9999px; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; }
        th, td { border: 1px solid #e2e8f0; padding: 4px 8px; text-align: left; white-space: nowrap; max-width: 300px; overflow: hidden; text-overflow: ellipsis; }
        th { background: #f1f5f9; font-weight: 600; color: #334155; position: sticky; top: 42px; }
        tr:hover td { background: #f0f9ff; }
        tr:nth-child(even) td { background: #f8fafc; }
      </style>
      </head><body>
        <div class="toolbar">
          <h1>#{ERB::Util.html_escape(filename)}</h1>
          <span class="badge">#{body_rows.size} rows</span>
        </div>
        <div style="overflow-x:auto;">
          <table><thead><tr>#{header_html}</tr></thead><tbody>#{rows_html}</tbody></table>
        </div>
        <script>document.addEventListener('keydown',function(e){if(e.key==='Escape')window.parent.postMessage('close-preview-modal','*')});</script>
      </body></html>
    HTML
  rescue => e
    build_text_preview_html(filepath, filename)
  end

  # 텍스트 파일 → 코드 뷰어 스타일 미리보기
  def build_text_preview_html(filepath, filename)
    content = IO.read(filepath, 100_000, encoding: "UTF-8") || ""  # 100KB 제한
    lines = content.lines.first(2000)

    lines_html = lines.each_with_index.map do |line, idx|
      num = idx + 1
      "<tr><td class='ln'>#{num}</td><td class='code'>#{ERB::Util.html_escape(line.chomp)}</td></tr>"
    end.join

    <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><title>#{ERB::Util.html_escape(filename)}</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace; background: #1e293b; color: #e2e8f0; }
        .toolbar { position: sticky; top: 0; z-index: 10; background: #0f172a; border-bottom: 1px solid #334155;
                   padding: 8px 16px; display: flex; align-items: center; gap: 8px; }
        .toolbar h1 { font-size: 13px; font-weight: 600; color: #94a3b8; }
        .badge { font-size: 11px; color: #94a3b8; background: #334155; padding: 2px 8px; border-radius: 9999px; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; line-height: 1.6; }
        .ln { color: #475569; text-align: right; padding: 0 12px; user-select: none; white-space: nowrap; border-right: 1px solid #334155; }
        .code { padding: 0 16px; white-space: pre; }
        tr:hover { background: #1e3a5f33; }
      </style>
      </head><body>
        <div class="toolbar">
          <h1>#{ERB::Util.html_escape(filename)}</h1>
          <span class="badge">#{lines.size} lines</span>
        </div>
        <table>#{lines_html}</table>
        <script>document.addEventListener('keydown',function(e){if(e.key==='Escape')window.parent.postMessage('close-preview-modal','*')});</script>
      </body></html>
    HTML
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
