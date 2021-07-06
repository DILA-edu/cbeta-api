# 讀純文字檔，產生 xml 給 sphinx 做 index

require 'csv'
require 'fileutils'
require 'json'
require 'set'
require 'cbeta'

class SphinxT2X
  PUNCS = /[\n\.\(\)\[\]\-\d　．。，、？！：；／「」〃『』《》＜＞〈〉〔〕［］【】〖〗（）…—]/
  def initialize
    @cbeta = CBETA.new
    @dynasty_labels = read_dynasty_labels
  end
  
  def convert
    @id = 0
    
    folder = Rails.root.join('data', 'cbeta-xml-for-sphinx')
    FileUtils.mkpath(folder)
    
    fn = Rails.root.join(folder, 'without-puncs.xml')
    @f_wo = open_xml(fn)
    
    src = Rails.root.join('data', 'cbeta-txt')
    Dir.entries(src).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(src, f)
      convert_canon(f, path)
    end
    
    close_xml(@f_wo)
    puts "output file: #{fn}"    
  end
  
  private
  
  def close_xml(f)
    f.write '</sphinx:docset>'
    f.close
  end


  def convert_canon(canon, folder)
    $stderr.puts "sphinx t2x: #{folder}"
    @canon = canon
    @canon_order = CBETA.get_sort_order_from_canon_id(canon)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(folder, f)
      convert_vol(f, path)
    end
  end
  
  def convert_juan(text_file_path)
    basename = File.basename(text_file_path, '.txt')
    @juan = strip_zero(basename)
    
    data = {
      title: '',
      byline: ''
    }
    get_info_from_work(@work, data)
  
    @id += 1
    
    data[:content] = File.read(text_file_path)
  
    # 要把標點去掉，才能找到跨標點的詞，例如「不也天中天」
    # 半形數字也去掉
    # 半形空格不能去掉，否則會搜不到：Pāli Text Society
    data[:content].gsub!(PUNCS, '')
    write_xml(@f_wo, data)
  end
  
  def convert_vol(vol, folder)
    $stderr.puts "sphinx t2x #{vol}"
    @vol = vol
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(folder, f)
      @xml_file = f
      convert_work(path)
    end
  end

  def convert_work(folder)
    @work = @xml_file.sub(/^(#{CBETA::CANON})\d{2,3}n(.*)$/, '\1\2')

    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(folder, f)
      convert_juan(path)
    end
  end
  
  def get_info_from_work(work, data)
    w = Work.find_by n: work
    abort "在 works table 裡找不到 #{work}" if w.nil?
    
    data[:title]     = w.title
    data[:byline]    = w.byline
    data[:work_type] = w.work_type    unless w.work_type.nil?

    unless w.time_dynasty.blank?
      d = w.time_dynasty
      data[:dynasty] = @dynasty_labels[d] || d
    end

    data[:time_from]        = w.time_from    unless w.time_from.nil?
    data[:time_to]          = w.time_to      unless w.time_to.nil?
    data[:creators]         = w.creators         unless w.creators_with_id.nil?
    data[:creators_with_id] = w.creators_with_id unless w.creators_with_id.nil?

    data[:category]     = w.category
    data[:category_ids] = w.category_ids
    data[:alt]          = w.juan_list unless w.alt.nil?
    data[:juan_list]    = w.juan_list
    data[:juan_start]   = w.juan_start
    
    return if w.creators_with_id.nil?
    
    a = []
    w.creators_with_id.split(';').each do |creator|
      creator.match(/A(\d{6})/) do
        a << $1.to_i.to_s
      end
    end
    data[:creator_id] = a.join(',')
  end
  
  def open_xml(fn)
    f = File.open(fn, 'w')
    f.puts %(<?xml version="1.0" encoding="utf-8"?>\n)
    f.puts "<sphinx:docset>\n"
    f
  end

  def read_dynasty_labels
    r = {}
    fn = Rails.root.join('data-static', 'dynasty-order.csv')
    CSV.foreach(fn, headers: true) do |row|
      row['dynasty'].split('/').each do |d|
        r[d] = row['dynasty']
      end
    end
    r
  end

  def strip_zero(s)
    s.sub(/^0*(\d*)$/, '\1')
  end
  
  def write_xml(f, data)
    s = "<sphinx:document id='#{@id}'>\n"
    s += "<canon>#{@canon}</canon>\n"
    s += "<canon_order>#{@canon_order}</canon_order>\n"
    s += "<xml_file>#{@xml_file}</xml_file>\n"
    s += "<vol>#{@vol}</vol>\n"
    s += "<work>#{@work}</work>\n"
    s += "<juan>#{@juan}</juan>\n"
    
    data.each_pair do |k,v|
      s += "<#{k}>#{v}</#{k}>\n"
    end
    
    s += "</sphinx:document>\n"
    f.puts s
  end

end