# 將 info-tmp.dat 依 suffix array 順序排序為 info.dat, info-b.dat

require 'yaml'
require 'chronic_duration'
#require_relative 'kwic_helper'
require_relative '../../app/services/suffix_info'

class KwicSortInfo
  INFO_SIZE = SuffixInfo::SIZE

  def run
    source = File.join(Rails.configuration.x.kwic.temp, 'sa')

    t1 = Time.now
    begin
      handle_folder(source)
    rescue
      abort "sort-info.rb 發生錯誤: #{$!}"
    end

    print "花費時間："
    puts ChronicDuration.output(Time.now - t1)
  end

  def exist_all_text?(folder)
    p = File.join(folder, 'all.txt')
    File.exist? p
  end
  
  def handle_folder(folder)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      next if f == 'juan'  # 單卷 info 檔，不排序

      print f + ' '
      path = File.join(folder, f)
      if exist_all_text?(path)
        sort_info_files(path)
      elsif Dir.exist?(path)
        handle_folder(path)
      end
    end
  end
  
  def sort_info_file(folder, info, fn_sa, fn_info)
    sa_path = File.join(folder, fn_sa)
    sa = File.open(sa_path, 'rb') do |f|
      $size = f.size / 4
      b = f.read
      b.unpack('V*')
    end
    
    info_path = File.join(folder, fn_info)
    File.open(info_path, 'wb') do |f|
      sa.each do |i|
        if fn_info == 'info-b.dat'
          offset = ($size - i - 1) * INFO_SIZE
        else
          offset = i * INFO_SIZE
        end
        b = info[offset, INFO_SIZE]
        abort "read info error, #{info_path}, offset： #{i}" if b.nil?
        data = SuffixInfo::unpack(b)
        f.write(b)
      end
    end
  end
  
  def sort_info_files(folder)
    info_path = File.join(folder, 'info-tmp.dat')
    info = File.binread(info_path)
  
    # 在 rotate.rb 裡再移除 info-tmp.dat，
    # 以免 sorf-info.rb 執行到一半中斷的話，
    # 要再重新執行已經沒有 info-tmp.dat 了⋯⋯
    # server 如果 RAM 只有 4GB 會出現：failed to allocate memory (NoMemoryError)
    #File.delete(info_path) 
    
    sort_info_file(folder, info, 'sa.dat',   'info.dat')
    sort_info_file(folder, info, 'sa-b.dat', 'info-b.dat')
  end
end