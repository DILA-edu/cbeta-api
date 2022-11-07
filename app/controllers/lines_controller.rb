class LinesController < ApplicationController
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
      if params[:before] # 取得前幾行
        get_previous_lines(lh, params[:before].to_i, result)
      end
      lines = Line.where(linehead: lh)
      add_lines_to_result result, lines
      if params[:after] # 取得後幾行
        get_next_lines(lh, params[:after].to_i, result)
      end
    elsif params.key? :linehead_start and params.key? :linehead_end
      lines = Line.where(linehead: params[:linehead_start]..params[:linehead_end])
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
    lines = Line.where("linehead > ?", linehead).order(:linehead).first(after)
    add_lines_to_result result, lines
  end
  
  def get_previous_lines(linehead, before, result)
    lines = Line.where("linehead < ?", linehead).order(linehead: :desc).first(before)
    add_lines_to_result result, lines
  end
end
