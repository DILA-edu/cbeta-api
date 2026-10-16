class LinesController < ApplicationController  
  include ApiKeyAuthentication

  # 單次最多回傳行數。最大單卷 (B0170 第 3 卷) 約 1.65 萬行,
  # 取一整卷的請求不受影響; 防止 linehead_start..linehead_end 撈出整張表。
  MAX_LINES = 20_000

  def index
    t1 = Time.now

    if referer_cn?
      lh = params[:linehead] || params[:linehead_start]
      if filter_cn?(id: lh)
        my_render(EMPTY_RESULT)
        return
      end
    end

    result = []
    if params.key? :linehead
      lh = params[:linehead]
      before = line_count_param(:before)
      after = line_count_param(:after)
      if before # 取得前幾行
        get_previous_lines(lh, before, result)
      end
      lines = Line.where(linehead: lh)
      add_lines_to_result result, lines
      if after # 取得後幾行
        get_next_lines(lh, after, result)
      end
    elsif params.key? :linehead_start and params.key? :linehead_end
      lines = Line.where(linehead: params[:linehead_start]..params[:linehead_end])
      # count 加 limit 會變成 subquery, 不必數完整個範圍
      if lines.limit(MAX_LINES + 1).count > MAX_LINES
        raise CbetaError.new(400), "linehead_start 到 linehead_end 的範圍不得超過 #{MAX_LINES} 行"
      end
      add_lines_to_result(result, lines)
    end
    result.sort! { |x,y| x[:linehead] <=> y[:linehead] }
    r = {
      num_found: result.size,
      time: Time.now - t1,
      results: result
    }
    my_render r
  end
  
  private

  # before / after 參數: 沒帶時回傳 nil。to_i 沿用舊行為 (非數字視為 0),
  # 但負數會讓 first(n) 丟 ArgumentError 變成 500, 改回 400。
  def line_count_param(key)
    return nil unless params[key]

    n = params[key].to_i
    if n.negative? || n > MAX_LINES
      raise CbetaError.new(400), "#{key} 參數必須介於 0 到 #{MAX_LINES}"
    end
    n
  end
  
  def add_lines_to_result(result, lines)
    lines.each do |line|
      data = {
        linehead: line.linehead,
        html: line.html
      }
      data[:notes] = JSON.parse(line.notes) unless line.notes.blank?
      result << data
    end
  end
  
  def filter_html(html)
    @notes = {}
    doc = Nokogiri::HTML(html)
    r = filter_traverse(doc.root)
    r.strip
  end
  
  def filter_node(e)
    return e.text if e.text?
    
    r = ''
    case e.name
    when 'a'
      if e['class'] == 'noteAnchor'
        n = e['href'][1..-1]
        @notes[n] = @html_doc.at_css("##{n}").text
        r = %(<a class="noteAnchor" href="##{n}"></a>)
      end
    when 'span'
      puts e['id']
      r = case e['class']
      when 'lb'
        e.to_html
      when 'lineInfo'
        ''
      else
        filter_traverse(e)
      end
    else
      r = filter_traverse(e)
    end
    r
  end
  
  def filter_traverse(e)
    r = ''
    e.children.each { |c| 
      r += filter_node(c)
    }
    r    
  end  
  
  def get_next_lines(linehead, after, result)
    line = Line.find_by(linehead:)
    return if line.nil? # linehead 不存在: 不加前後行, 結果為空

    lines = Line.where("ser_no > ?", line.ser_no).order(:ser_no).first(after)
    add_lines_to_result result, lines
  end
  
  def get_previous_lines(linehead, before, result)
    line = Line.find_by(linehead:)
    return if line.nil? # linehead 不存在: 不加前後行, 結果為空

    lines = Line.where("ser_no < ?", line.ser_no).order(ser_no: :desc).first(before)
    add_lines_to_result result, lines
  end
end
