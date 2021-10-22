require 'chronic_duration'
require 'cbeta'
require_relative 'cbeta_epub2'
require_relative '../cbeta_p5a_share'

class CbetaEbook
  def initialize(config)
    options = {
      version: config[:quarter], # ex: 2019.Q3
      front_page: File.join(config[:epub_template], 'readme.xhtml'),
      front_page_title: '編輯說明',
      back_page: File.join(config[:epub_template], 'donate.xhtml'),
      back_page_title: '贊助資訊',
      covers: config[:covers],
      gaiji_base: config[:gaiji],
      figures: config[:figures],
      template: config[:epub_template],
      sd_gif: File.join(config[:git], 'sd-gif'),
      rj_gif: File.join(config[:git], 'rj-gif')
    }
    @converter = CbetaEpub.new(options)
    @xml_base = config[:xml]
    @out_base = config[:epub]
  end

  # 轉全部: arg = nil
  # 只轉嘉興藏: arg = 'J'
  # 從 J 轉到 ZW: arg = 'J..ZW': 
  def convert(arg=nil)
    puts "開始製作 EPUB"
    t1 = Time.now
    if arg.nil?
      puts "清除舊資料"
      FileUtils.rm_rf(@out_base)
      FileUtils.makedirs(@out_base)
      each_canon(@xml_base) do |c|
        convert_canon(c)
      end
    elsif arg.include?('..')
      c1, c2 = arg.split('..')
      Dir.entries(@xml_base).sort.each do |f|
        next if f.start_with?('.')
        next if f.size > 2
        next if (f < c1) or (f > c2)
        convert_canon(f)
      end
    else
      convert_canon(arg)
    end
    print "產生 EPUB 花費時間："
    puts ChronicDuration.output(Time.now - t1)  
  end

  private

  def convert_canon(canon)
    src = File.join(@xml_base, canon)
    dest = File.join(@out_base, canon)
    @converter.convert_folder(src, dest)
  end

  include CbetaP5aShare
end