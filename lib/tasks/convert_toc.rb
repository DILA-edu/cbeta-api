require 'json'
require 'nokogiri'
require 'zhongwen_tools'
require 'zhongwen_tools/core_ext/integer'
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
    @canon = canon
    path = File.join(@xml_root, canon)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      $stderr.puts "convert_toc #{@vol}"
      p = File.join(path, f)
      convert_vol(p)
    end
    @work = nil
    check_work
  end

  private

  def check_work
    if @work != @previous_work
      unless @previous_work.nil?
        s = JSON.pretty_generate(@toc)
        folder = File.join(@out_root, @previous_canon)
        Dir.mkdir(folder) unless Dir.exist?(folder)
        fn = @previous_work+'.json'
        fn = File.join(folder, fn)
        File.write(fn, s)
      end
      @toc = {
        "mulu" => [],
        "juan" => []
      }
      @toc_stack = [@toc['mulu']]

      @previous_canon = @canon
      @previous_work = @work
    end
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
          s = '第' + s.to_i.to_zht
        end
      else
        s = '第' + @juan.to_zht
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
    data[:title].match(/^(\d+)/) do
      data[:n] = $1.to_i
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
  
  def convert_vol(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      if f.match(/^.*?n(.*?)\.xml$/)
        @work = @canon + $1
        @file = "#{@vol}n#{$1}"
        @work = 'T0220' if @work.start_with? 'T0220'
        p = File.join(path, f)
        convert_work(p)
      else
        abort "work id error: #{f}"
      end
    end
  end
  
  def convert_work(xml_path)
    check_work
    get_info_from_xml(xml_path)    
  end
  
  def toc_n(stack)
    suffix = stack.map { |i| i.to_s }
    n = @work + '.' + suffix.join('.')
    suffix.pop
    parent = @work + '.' + suffix.join('.')
    return parent, n
  end

  include CbetaP5aShare
end
