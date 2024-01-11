# 讀 CBETA XML，切塊，產生 xml 給 sphinx 做 index

require 'fileutils'
require 'json'
require 'set'
require 'cbeta'
require_relative 'cbeta_p5a_share'
require_relative 'sphinx-share'

class SphinxChunks
  MAX = 100 # 區塊 最長 長度
  OVERLAP = 50 # 前後區塊 重疊 字數
  CB_PRIORITY = %w[uni_char norm_uni_char norm_big5_char PUA] # 缺字 呈現 優先序

  def initialize
    f = Rails.root.join('log', 'sphinx-chunks.log')
    @log = File.open(f, 'w')

    @xml_root = Rails.application.config.cbeta_xml
    @cb_gaiji = CBETA::Gaiji.new
    @dynasty_labels = read_dynasty_labels
  end

  def convert
    puts Rails.configuration.cb.git
    exit
    t1 = Time.now
    @count = 0
    folder = Rails.root.join('data', 'sphinx-xml')
    FileUtils.mkpath(folder)
    
    fn = Rails.root.join(folder, 'chunks.xml')
    @fo = open_xml(fn)
    convert_all  
    close_xml(@fo)
    puts "\n總筆數： #{@count}"
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  end  

  private

  def add_text(text)
    if @blocks.empty?
      @blocks << { lb: @lb, text: ''}
    end
  
    block = @blocks[-1]
    block[:text] << text
  
    if block[:text].size == OVERLAP
      @blocks << { lb: @lb, text: '' }
    else
      while @blocks[-1][:text].size > OVERLAP
        b = @blocks[-1]
        suffix = b[:text][OVERLAP..-1]
        b[:text] = b[:text][0...OVERLAP]
        @blocks << { lb: @lb, text: suffix }
      end
    end
  end
  
  def close_xml(f)
    f.write '</sphinx:docset>'
    f.close
  end

  def convert_all
    each_canon(@xml_root) do |c|
      convert_canon(c)
    end
  end

  def convert_canon(c)
    puts "convert canon: #{c}"
    @canon = c
    @titles = read_titles

    folder = File.join(@xml_root, @canon)
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      convert_vol(vol)
    end
  end
  
  def convert_sutra(xml_fn)
    @basename = File.basename(xml_fn, '.*')
    puts "sphinx-chunks.rb #{@basename}"
    @first_juan = true
    @blocks = []
    @buf = []
    @work_id = CBETA.get_work_id_from_file_basename(@basename)
    
    @work_info = get_info_from_work(@work_id, exclude: [:juan_list, :juan_start])
    raise '@work_info is nil' if @work_info.nil?

    doc = File.open(xml_fn) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    body = doc.at_xpath('//body')
    traverse(body)
    write_chunks
  end
  
  def convert_vol(vol)
    @vol = vol
    
    source = File.join(@xml_root, @canon, vol)
    Dir.entries(source).sort.each do |f|
      next if f.start_with? '.'
      fn = File.join(source, f)
      convert_sutra(fn)
    end
  end

  def e_g(e)
    id = e['ref'].delete_prefix('#')
    char = @cb_gaiji.to_s(id, cb_priority: CB_PRIORITY)
    if char.nil?
      abort "\n#{id} 在缺字資料庫 找不到"
    end
    add_text(char)
    add_text(' ') if id.start_with?('SD')
  end
  
  def e_lb(e)
    return '' if e['type']=='old'
    return '' if e['ed'] != @canon # 卍續藏裡有 新文豐 版行號
  
    @lb = e['n']
    unless @blocks.empty?
      b = @blocks.last 
      if b[:lb].nil? or b[:text].empty?
        b[:lb] = @lb 
      end
    end
  end
  
  def e_milestone(e)
    return unless e['unit'] == 'juan'
    if @first_juan
      @first_juan = false
    else
      write_chunks
    end
    @juan = e['n'].to_i
    @chunk_n = 0
  end
  
  def e_note(e)
    if e.key?('type')
      return if %w[add equivalent orig mod rest star].include?(e['type'])
      return if e['type'].match?(/^cf\d+$/)
    end
    
    return if e.key?('place') and e['place'] == 'foot'
  
    add_text('(')
    traverse(e)
    add_text(')')
  end
  
  def handle_element(e)
    case e.name
    when 'docNumber', 'mulu', 'rdg'
    when 'caesura'
      add_text(' ')
    when 'byline', 'cell', 'div', 'head', 'item', 'juan', 'l', 'p', 'row'
      traverse(e)
      add_text(' ')
    when 'foreign'
      return if e['place'] == 'foot'
      traverse(e)
    when 'g'  then e_g(e)
    when 'lb' then e_lb(e)
    when 'milestone' then e_milestone(e)
    when 'note' then e_note(e)
    when 't'
      return if e['place'] == 'foot'
      traverse(e)
      add_text(' ') unless e.parent['type'] == 'app'
    else
      traverse(e)
    end
  end
  
  def open_xml(fn)
    f = File.open(fn, 'w')
    f.puts %(<?xml version="1.0" encoding="utf-8"?>\n)
    f.puts "<sphinx:docset>\n"
    f
  end

  def read_titles
    src = File.join(Rails.configuration.x.work_info, "#{@canon}.json")
    JSON.load_file(src)
  end
  
  def traverse(e)
    e.children.each do |c|
      next if c.comment?
      if c.text?
        s = c.text.gsub(/[\s\u2500-\u257f]+/, '')  # Box Drawing
        add_text(s)
      elsif c.element?
        handle_element(c)
      end
    end
  end

  def write_chunk(lb, text)
    if text.size > MAX
      abort "size 大於 #{MAX}, text: #{text}" 
    end
  
    @count += 1
    xml = <<~XML
      <sphinx:document id="#{@count}">
        <canon>#{@canon}</canon>
        <vol>#{@vol}</vol>
        <file>#{@basename}</file>
        <work>#{@work_id}</work>
        <juan>#{@juan}</juan>
        <lb>#{lb}</lb>
        <linehead>#{CBETA.get_linehead(@basename, lb)}</linehead>
        <content>#{text}</content>
    XML

    @work_info.each_pair do |k,v|
      xml << "  <#{k}>#{v}</#{k}>\n"
    end

    xml << "</sphinx:document>\n"
    @fo.puts xml
    @chunk_n += 1
  end

  def write_chunks
    total = 0
    @blocks.each { |b| total += b[:text].size }
  
    b1 = nil
    b2 = nil
    
    until @blocks.empty?
      if b2.nil?
        b1 = @blocks.shift
      else
        b1 = b2
      end
  
      if @blocks.empty?
        write_chunk(b1[:lb], b1[:text])
      else
        b2 = @blocks.shift
        write_chunk(b1[:lb], b1[:text] + b2[:text])
      end    
    end
  
    @blocks = []
  end
  
  include CbetaP5aShare
  include SphinxShare
end
