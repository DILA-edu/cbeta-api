# frozen_string_literal: true

# v1/tools/fetch — resolve a CBETA linehead id to grounded passage text.
#
# Flow:
#   1. juans#goto (via goto_linehead) to validate the id and resolve location
#      metadata (work, vol, file, lb, juan, title).
#   2. lines#index logic (via Line model) to collect context lines
#      (before: 3, after: 3) centered on the linehead.
#   3. Strip HTML to plain text and return the normalized fetch envelope.
module V1
  class FetchController < ApplicationController
    include ToolEnvelope

    rescue_from StandardError, with: :tool_error_handler

    def fetch
      id = params[:id].to_s.strip
      return tool_error(code: 400, message: 'Missing required parameter: id') if id.empty?

      location = goto_linehead(linehead: id)

      if location.nil? || location == EMPTY_RESULT
        return tool_error(code: 404, message: "Linehead not found: #{id}")
      end

      if location[:error]
        err = location[:error]
        return tool_error(code: err[:code] || 404, message: err[:message].to_s)
      end

      linehead = location[:linehead] || id
      lines    = context_lines(linehead, before: 3, after: 3)
      work     = location[:work]
      title    = Work.find_by(n: work)&.title.to_s
      text     = lines.map { |l| strip_html(l[:html]) }.reject(&:empty?).join("\n")

      my_render({
        id: id,
        title: title,
        text: text,
        url: "https://cbetaonline.dila.edu.tw/#{work}_%03d" % location[:juan].to_i,
        metadata: {
          work:          work,
          file:          location[:file],
          juan:          location[:juan],
          vol:           location[:vol],
          lb:            location[:lb],
          linehead:      linehead,
          line_count:    lines.size,
          notes_present: lines.any? { |l| l[:notes].present? }
        }.compact
      })
    end

    private

    def context_lines(linehead, before:, after:)
      line = Line.find_by(linehead:)
      return [] if line.nil?

      result = []
      Line.where("ser_no < ?", line.ser_no).order(ser_no: :desc).first(before).reverse_each do |l|
        result << build_line_data(l)
      end
      result << build_line_data(line)
      Line.where("ser_no > ?", line.ser_no).order(:ser_no).first(after).each do |l|
        result << build_line_data(l)
      end
      result
    end

    def build_line_data(line)
      data = { linehead: line.linehead, html: line.html }
      data[:notes] = JSON.parse(line.notes) unless line.notes.blank?
      data
    end

    def strip_html(html)
      Nokogiri::HTML(html).text.gsub(/\s+/, ' ').strip
    end
  end
end
