# 讀純文字檔，產生 xml 給 manticore 做 index

require 'csv'
require 'fileutils'
require 'json'
require 'set'
require 'cbeta'
require_relative 'sphinx-share'

class ManticoreT2X
  def initialize
    @cbeta = CBETA.new
    @dynasty_labels = read_dynasty_labels
    @cbs = CbetaString.new
  end
  
  def convert
    @id = 0
    
    folder = Rails.root.join('data', 'manticore-xml')
    FileUtils.mkpath(folder)
    
    fn = Rails.root.join(folder, 'text.xml')
    @f_wo = open_xml(fn)
    
    @src  = Rails.root.join('data', "cbeta-txt-with-notes-for-manticore")
    @src2 = Rails.root.join('data', "cbeta-txt-without-notes-for-manticore")
    Dir.entries(@src).sort.each do |f|
      next if f.start_with? '.'
      convert_canon(f)
    end
    
    close_xml(@f_wo)
    puts "output file: #{fn}"    
  end
  
  private
  
  def close_xml(f)
    f.write '</sphinx:docset>'
    f.close
  end

  def convert_canon(canon)
    puts "manticore t2x: #{canon}"
    @canon = canon
    @canon_order = CBETA.get_sort_order_from_canon_id(canon)
    folder = File.join(@src, canon)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      convert_vol(f)
    end
  end
  
  def convert_juan(rel_path)
    basename = File.basename(rel_path, '.txt')
    @juan = strip_zero(basename)
    
    data = {
      title: '',
      byline: ''
    }
    get_info_from_work(@work, data)
  
    @id += 1
    
    fn = File.join(@src, rel_path)
    s = File.read(fn)  
    data[:content] = @cbs.remove_puncs(s) # 要把標點去掉，才能找到跨標點的詞，例如「不也天中天」

    fn = File.join(@src2, rel_path)
    s = File.read(fn)  
    data[:content_without_notes] = @cbs.remove_puncs(s)

    write_xml(@f_wo, data)
  end
  
  def convert_vol(vol)
    puts "manticore t2x #{vol}"
    @vol = vol
    folder = File.join(@src, @canon, vol)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      @xml_file = f
      convert_work
    end
  end

  def convert_work
    @work = @xml_file.sub(/^(#{CBETA::CANON})\d{2,3}n(.*)$/, '\1\2')
    rel_path = File.join(@canon, @vol, @xml_file)
    folder = File.join(@src, rel_path)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      rel_path2 = File.join(rel_path, f)
      convert_juan(rel_path2)
    end
  end
    
  def open_xml(fn)
    f = File.open(fn, 'w')
    f.puts %(<?xml version="1.0" encoding="utf-8"?>\n)
    f.puts "<sphinx:docset>\n"
    f
  end


  def strip_zero(s)
    s.sub(/^0*(\d*)$/, '\1')
  end
  
  def write_xml(f, data)
    s = <<~XML
      <sphinx:document id='#{@id}'>
        <canon>#{@canon}</canon>
        <canon_order>#{@canon_order}</canon_order>
        <xml_file>#{@xml_file}</xml_file>
        <vol>#{@vol}</vol>
        <work>#{@work}</work>
        <juan>#{@juan}</juan>
    XML
    
    data.each_pair do |k,v|
      s << "<#{k}>#{v}</#{k}>\n"
    end
    
    s << "</sphinx:document>\n"
    f.puts s
  end

  include SphinxShare
end
