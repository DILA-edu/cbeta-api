# 根據 CBETA XML P5a 取得每卷的起始行號、結束行號

require 'cbeta'
require_relative '../cbeta_p5a_share'

class Juanline
  def produce
    @in = Rails.application.config.cbeta_xml
    @out = Rails.root.join('data', 'juan-line')
    FileUtils.rm_rf(@out)
    FileUtils.makedirs(@out)
    each_canon(@in) do |canon|
      handle_canon(canon)
    end
  end

  private

  def handle_canon(canon)
    $stderr.puts canon
    @juanline = {}
    path = File.join(@in, canon)
    Dir.entries(path).sort.each do |vol|
      next if vol.start_with? '.'
      handle_vol(canon, vol)
    end
    output(canon)
  end

  def handle_file(canon, vol, fn)
    basename = File.basename(fn, '.xml')
    work = CBETA.get_work_id_from_file_basename(basename)
    unless @juanline.key? work
      @juanline[work] = {}
    end
    data = @juanline[work]
    
    path = File.join(@in, canon, vol, fn)
    doc = File.open(path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!()
    
    lb = nil
    juan = nil
    doc.xpath('//milestone | //lb').each do |e|
      case e.name
      when 'lb'      
        if e['ed'] == canon
          lb = e['n']

          # 行號有可能不是數字開頭，例如 Y01n0001_pa001a01
          # 這樣 a001 會比 0001 大，排序比較會有問題
          # 所以把 a001 改成 0000a001, 排序就會在 0001 前面
          lb = "0000#{lb}" unless lb.match(/^\d/)

          abort 'lb 在 milestone 之前' if juan.nil?
          abort 'lb 在 milestone 之前' unless data.key? juan

          j = data[juan]
          j[:lb_begin] = lb unless j.key? :lb_begin
          j[:lb_end] = lb
        end
      when 'milestone'
        if e['unit']=='juan'
          juan = e['n']
          data[juan] = { vol: vol }
        end
      end
    end
  end

  def handle_vol(canon, vol)
    path = File.join(@in, canon, vol)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      handle_file(canon, vol, f)
    end
  end

  def output(canon)
    folder = File.join(@out, canon)
    Dir.mkdir(folder) unless Dir.exist? folder
    @juanline.each_pair do |work, v|
      s = JSON.pretty_generate(v)
      fn = File.join(folder, "#{work}.json")
      File.write(fn, s)
    end
  end

  include CbetaP5aShare
end