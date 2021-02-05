namespace :convert do
  
  desc "XML 轉 Docusky"
  task :docusky, [:canon] => :environment do |t, args|
    require 'tasks/convert_docusky'
    c = ConvertDocusky.new
    c.convert(args[:canon])
  end
  
  desc "由 XML 轉出 JuanLine 檔"
  task :juanline => :environment do
    require_relative 'quarterly/juanline'
    Juanline.new.produce
  end

  desc "將 純文字版 自動分詞"
  task :seg, [:canon] => :environment do |t, args|
    require 'tasks/convert_seg'
    c = ConvertSeg.new
    c.convert(args[:canon])
  end

  desc "XML 轉 HTML"
  # 只轉某部經： rake convert:x2h[2020-09,T10n0297]
  task :x2h, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_x2h'
    c = ConvertX2h.new
    c.convert(args[:publish], args[:canon])
  end

  desc "XML 轉 下載用 HTML"
  task :x2h4d, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_x2h_for_download'
    c = ConvertX2hForDownload.new
    c.convert(args[:publish], args[:canon])
  end

  desc "XML 轉 下載用 Text"
  task :x2t4d, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_x2t_for_download'
    c = ConvertX2tForDownload.new
    c.convert(args[:publish], args[:canon])
  end
  
  desc "XML 轉 目次 toc JSON 檔"
  task :toc, [:arg1] => :environment do |t, args|
    require 'tasks/convert_toc'
    c = ConvertToc.new
    c.convert(args[:arg1])
  end
  
end