require 'json'
require 'nokogiri'
require 'int_to_zht'
require_relative 'cbeta_p5a_share'

class ConvertToc
  
  def initialize
    @xml_root = Rails.application.config.cbeta_xml
    @out_root = Rails.root.join('data', 'toc')
    Dir.mkdir(@out_root) unless Dir.exist?(@out_root)
  end

  def convert(arg)
    if arg.nil?
      convert_all
    else
      convert_canon(arg)
    end
  end
  
  def convert_all
    @previous_work = nil
    each_canon(@xml_root) do |c|
      convert_canon(c)
    end
  end
  
  def convert_canon(canon)
    puts "convert_canon: #{canon}"
    @canon = canon

    # 注意不能簡單排序
    # B15n0088 會排在 B15na014 前面，接不到 B16n0088

    path = File.join(@xml_root, canon)
    works = works_in_canon(path)
    works.each do |work, files|
      init_work
      files.each do |f|
        @file = File.basename(f, '.*')
        get_info_from_xml(f)
      end
      write_toc(work)
    end
  end

  private

  def init_work
    @toc = {
      "mulu" => [],
      "juan" => []
    }
    @toc_stack = [@toc['mulu']]
  end
  
  def get_info_from_xml(xml_path)
    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    
    doc.search('//lb|//milestone|//mulu').each do |e|
      case e.name
      when 'lb'        then handle_lb(e)
      when 'milestone' then handle_milestone(e)
      when 'mulu'      then handle_mulu(e)
      end
    end
  end
  
  def handle_lb(e)
    unless @canon=='X' and e['ed'].start_with? 'R'
      @lb = e['n']
    end
  end
  
  def handle_milestone(e)
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
    end
  end
  
  def handle_mulu(e)
    if e['type'] == "卷"
      handle_mulu_juan(e)
    else
      handle_mulu_toc(e)
    end
  end

  def handle_mulu_juan(e)
    data = { file: @file, juan: @juan, lb: @lb }
    s = e.text
    if s.empty?
      if e.key? 'n'
        s = e['n']
        if s.match(/^\d+$/)
          s = '第' + IntToZht.convert(s.to_i)
        end
      else
        s = '第' + IntToZht.convert(@juan)
      end
    end
    data[:title] = s
    @toc['juan'] << data
  end

  def handle_mulu_toc(e)
    return if e.text.empty?
    
    level = e['level'].to_i
    while @toc_stack.size > level
      @toc_stack.pop
    end
    current = @toc_stack[-1]
    data = { title: e.text, file: @file, juan: @juan, lb: @lb }
    data[:type] = e['type'] if e.key?('type')
    if m = data[:title].match(/^(\d+)/)
      data[:n] = $1.to_i
    elsif e.key?('n')
      data[:n] = e['n'].to_i
    end

    if current.is_a?(Hash)
      current[:isFolder] = true
      current[:children] = []
      @toc_stack[-1] = current[:children]
      current = @toc_stack[-1]
    end
    current << data
    @toc_stack << data
  end
    
  def convert_work(xml_path)
    check_work
    get_info_from_xml(xml_path)    
  end

  def int_to_zht(number)
    chinese_numerals = {
      0 => "零", 1 => "一", 2 => "二", 3 => "三", 4 => "四", 5 => "五",
      6 => "六", 7 => "七", 8 => "八", 9 => "九", 10 => "十"
    }
    
    if number < 10
      return chinese_numerals[number]
    elsif number < 20
      return "十" + (number == 10 ? "" : chinese_numerals[number % 10])
    else
      tens = number / 10
      units = number % 10
      return chinese_numerals[tens] + "十" + (units == 0 ? "" : chinese_numerals[units])
    end
  end
  
  def toc_n(stack)
    suffix = stack.map { |i| i.to_s }
    n = @work + '.' + suffix.join('.')
    suffix.pop
    parent = @work + '.' + suffix.join('.')
    return parent, n
  end

  def works_in_canon(src)
    r = Hash.new { |h, k| h[k] = Array.new }
    Dir["#{src}/**/*.xml"].sort.each do |path|
      file = File.basename(path, '.*')
      work = CBETA.get_work_id_from_file_basename(file)
      r[work] << path
    end
    r
  end

  def write_toc(work)
    s = JSON.pretty_generate(@toc)
    folder = File.join(@out_root, @canon)
    Dir.mkdir(folder) unless Dir.exist?(folder)
    fn = "#{work}.json"
    fn = File.join(folder, fn)
    File.write(fn, s)
  end

  include CbetaP5aShare
end
