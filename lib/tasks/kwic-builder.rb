require 'fileutils'
require 'date'
require 'json'
require 'yaml'
require_relative '../../app/services/suffix_info'

class KwicBuilder
  attr_accessor :juan, :offset, :relative_path, :text_with_punc, :canon, :vol, :work, :sa_units
  
  PUNCS = "\n.()[]-　．。，、？！：；／「」『』《》＜＞〈〉〔〕［］【】〖〗（）…—─▆"
  
  def initialize
    @work_base = Rails.configuration.x.kwic.temp
    @sa_base = File.join(@work_base, 'sa')
    
    # work id 對應 部類名稱
    fn = Rails.root.join('data-static', 'categories.json')
    s = File.read(fn)
    @categories = JSON.parse(s)

    if Rails.env == 'cn'
      @sa_units = ['juan']
    else
      @sa_units = %w(juan work canon category all)
    end

    @html_base = Rails.configuration.x.kwic.html
    @juan_cross_vol = chk_juan_cross_vol(@html_base)
  end
  
  def abs_sa_path(sa_unit, fn)
    relative_path = case sa_unit
    when 'juan'     then File.join(@work, @juan)
    when 'work'     then File.join(@work)
    when 'canon'    then File.join(@canon)
    when 'category' then File.join(@category)
    when 'all'      then ''
    else
      abort "error: 錯誤的 sa_unit"
    end
  
    folder = File.join(@sa_base, sa_unit, relative_path)
    FileUtils.mkdir_p folder
    File.join(folder, fn)
  end
  
  # 清除舊資料
  def clear_old_data
    FileUtils.remove_dir(@sa_base) if Dir.exist? @sa_base
    FileUtils.makedirs(@sa_base)
    
    f = File.join(@work_base, 'text')
    FileUtils.remove_dir(f) if Dir.exist? f
    FileUtils.makedirs(f)
  end
  
  def read_html_file(rel_path)
    @canon, @vol, @work_fn, @juan = rel_path.split('/')
    @work = CBETA.get_work_id_from_file_basename(@work_fn)
    @juan.sub!(/^(.*)\.html$/, '\1')
    @category = @categories[@work] || '其他'
  
    before_parse_html
  
    fn = File.join(@html_base, rel_path)
  
    doc = File.open(fn) { |f| Nokogiri::HTML(f) }
    body = doc.at_xpath('/html/body')
  
    r = traverse(body)
    @sa_units.each { |sa_unit| 
      write_info(sa_unit) 
    }
    
    r  
  end
    
  private
    
  def before_parse_html
    @info = ''
    @text_with_punc = ''

    unless @juan_cross_vol["#{@work_fn}_#{@juan}"] == 2
      @offset = 0
    end
  end

  def chk_juan_cross_vol(html_base)
    puts "檢查卷跨冊"
    prev_work_fn = nil
    prev_juan = nil
    r = {}
    Dir.entries(html_base).sort.each do |canon|
      next if canon.start_with?('.')
      p1 = File.join(html_base, canon)
      Dir.entries(p1).sort.each do |vol|
        next if vol.start_with?('.')
        p2 = File.join(p1, vol)
        Dir.entries(p2).sort.each do |work_fn|
          next if work_fn.start_with?('.')
          work = CBETA.get_work_id_from_file_basename(work_fn)
          p3 = File.join(p2, work_fn)
          Dir.entries(p3).sort.each do |juan_fn|
            next if juan_fn.start_with?('.')
            juan = File.basename(juan_fn, '.*')
            current_juan = "#{work}_#{juan}"
            if current_juan == prev_juan
              r["#{prev_work_fn}_#{juan}"] = 1
              r["#{work_fn}_#{juan}"] = 2
            else
              prev_juan = current_juan
            end
          end
          prev_work_fn = work_fn
        end
      end
    end
    p r
    r
  end

  def create_suffix_info()
    data = {
      vol: @vol,
      work: @work,
      juan: @juan.to_i,
      offset_in_text_with_punc: @offset,
      lb: @lb
    }
    SuffixInfo.new(data)
  end
  
  def handle_text(e)
    s = e.content()
    return '' if s.empty?
    r = ''
    @text_with_punc += s
    s.each_char do |c|
      unless PUNCS.include? c # 去除標點
        @info += create_suffix_info.pack
        r += c
      end
      @offset += 1 # 記錄該字元位於該卷文字中的位置，含標點
    end
    r
  end
  
  def traverse(parent)
    r = ''
    @lb = ''
    parent.children.each do |e|
      next if e.comment?
      if e.text?
        r += handle_text(e)
      elsif e.name == 'a'
        @lb = e['id']
      end
    end
    
    if @juan_cross_vol["#{@work_fn}_#{@juan}"] == 1
      puts "卷跨冊的上半部，最後不加空字元：#{@work_fn}_#{@juan}"
    else
      r += 0.chr
      @text_with_punc += 0.chr
      @info += create_suffix_info.pack
    end

    r
  end    
  
  def write_info(sa_unit)
    # 單卷 info 資料檔，不另排序
    if sa_unit == 'juan'
      fn = 'info.dat'
    else
      fn = 'info-tmp.dat'
    end

    fn = abs_sa_path(sa_unit, fn)
    f = File.open(fn, 'ab')
    f.write(@info)
    f.close
  end  
  
end

# 將數字轉為加上千位號的字串
def n2c(n)
  n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end

def progress(msg)
  puts Time.now.strftime("%Y-%m-%d %H:%M:%S")
  puts msg
end