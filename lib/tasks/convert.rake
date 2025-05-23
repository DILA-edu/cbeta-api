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

  desc "XML 轉 Change Log 比對用 Text Normal 版"
  task :x2t, [:q] => :environment do |t, args|
    v = args[:q] # 例: 2021Q1
    src = Rails.configuration.cbeta_xml
    gaiji = Rails.configuration.cbeta_gaiji
    dest = File.join("/home/ray/cbeta-change-log", "cbeta-normal-#{v}")
    require_relative 'quarterly/p5a_to_text'
    c = P5aToText.new(src, dest, gaiji_base: gaiji)
    c.convert
  end

  desc "XML 轉 下載用 Text"
  task :x2t4d, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_x2t_for_download'
    ConvertX2tForDownload.new.convert(args[:publish], args[:canon])
  end
  
  desc "XML 轉 下載用 Text (含校注)"
  task :x2t4d2, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_x2t4d2'
    ConvertX2T4D2.new.convert(args[:publish], args[:canon])
  end

  desc "XML 轉 xml4docx 格式 (用來轉 docx)"
  task :xml4docx, [:publish, :canon] => :environment do |t, args|
    require 'tasks/convert_xml4docx'
    XMLForDocx.new.convert(args[:publish], args[:canon])
  end

  task :xml4docx1, [:publish, :canon, :vol] => :environment do |t, args|
    require 'tasks/xml4docx1'
    xml_root = Rails.application.config.cbeta_xml
    dest1 = Rails.root.join('data', 'xml4docx1')
    XMLForDocx1.new(xml_root, dest1).convert(args)
  end

  task :xml4docx2, [:filter] => :environment do |t, args|
    require 'tasks/xml4docx2'
    dir1 = Rails.root.join('data', 'xml4docx1')
    dir2 = Rails.root.join('data', 'xml4docx2')
    XMLForDocx2.new.convert(dir1, dir2, filter: args[:filter])
  end

  task :xml4docx2t => :environment do
    require 'tasks/convert_xml4docx2t'
    dir1 = Rails.root.join('data', 'xml4docx2')
    dir2 = Rails.root.join('data', 'xml4docx2t')
    XMLForDocxToText.new.convert(dir1, dir2)
  end

  desc "XML 轉 目次 toc JSON 檔"
  task :toc, [:arg1] => :environment do |t, args|
    require 'tasks/convert_toc'
    c = ConvertToc.new
    c.convert(args[:arg1])
  end
  
end
