# 讀入每卷 html, 連成一個 all.txt, 並儲存相關資訊 info.dat

require 'benchmark'
require 'chronic_duration'
require 'fileutils'
require 'pp'
require 'json'
require 'nokogiri'
require 'yaml'
require 'cbeta'
require_relative 'kwic-builder.rb'

class KwicHtml2Text
  def initialize
    @work_base = Rails.configuration.x.kwic.temp
  end

  def convert(canon, vol, inline_note)
    # main
    t1 = Time.now

    puts "clear old data"
    @builder = KwicBuilder.new(inline_note)
    @builder.clear_old_data

    target = File.join(canon.to_s, vol.to_s)
    if target == '/'
      target = '' 
      puts "處理範圍: 全部"
    else
      puts "處理範圍: #{target}"
    end

    @size = 0
    @max_offset = 0
    read_text_from_folder(Rails.configuration.x.kwic.html, target)
    puts "size: " + n2c(@size)

    puts "max offset: " + n2c(@max_offset)

    print "text-all 花費時間："
    puts ChronicDuration.output(Time.now - t1)  
  end
  

  def read_file(base, rel_path)
    s1 = @builder.read_html_file(rel_path)
    @size += s1.size
    
    s2 = s1.reverse
    write_text(s1, s2)
    
    @max_offset = @builder.offset if @builder.offset > @max_offset
      
    folder = File.join(@work_base, 'text', @builder.canon, @builder.work)
    FileUtils.mkdir_p folder
    fn = File.join(folder, "#{@builder.juan}.txt")
    # 有「卷跨冊」的例外情況，所以要用 append mode
    File.open(fn, 'a:UTF-32LE') { |f| f.write(@builder.text_with_punc) }
  end

  def read_text_from_folder(base, folder)
    path = File.join(base, folder)
    entries = Dir.entries(path).sort
    entries.each do |f|
      next if f.start_with? '.'
      p = File.join(path, f)
      if folder.empty?
        relative = f
      else
        relative = File.join(folder,f)
      end
      if Dir.exist? p
        print "\n#{f} "
        read_text_from_folder(base, relative)
      else
        print f + ' '
        read_file(base, relative)
      end
    end
  end

  def write_text(s1, s2)
    fn = @builder.abs_sa_path('all.txt')
    
    # 要用 UTF－32LE, C++ 才能以 binary 直接讀入 int array
    File.open(fn, 'a:UTF-32LE') { |f| f.write(s1) }
    
    fn = @builder.abs_sa_path('all-b.txt')
    if File.exist? fn
      # 反向排序，後面的檔案要放前面
      FileUtils.mv fn, 'temp.txt'
      fo = File.open(fn, 'w:UTF-32LE') { |f| 
        f.write(s2)
        IO.copy_stream('temp.txt', f)
      }
      FileUtils.rm_f 'temp.txt'
    else
      File.write(fn, s2, encoding: 'UTF-32LE')
    end
  end


end