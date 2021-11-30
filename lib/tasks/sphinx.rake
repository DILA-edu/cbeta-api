namespace :sphinx do
  
  desc "將註解（校註、夾註）轉為 XML 供 Sphinx 建 Index"
  task :notes, [:arg1] => :environment do |t, args|
    require_relative 'sphinx-notes'
    SphinxNotes.new.convert
  end

  desc "XML 轉 txt"
  task :x2t, [:arg1] => :environment do |t, args|
    require_relative 'x2t_for_sphinx'

    src = Rails.application.config.cbeta_xml
    dest = Rails.root.join('data', 'cbeta-txt')
    puts "dest: #{dest}"
    
    if args[:arg1].nil?
      FileUtils.remove_dir(dest, force: true)
    else
      target_folder = File.join(dest, args[:arg1])
      FileUtils.remove_dir(target_folder, force: true)
    end
    
    # 為了要讓在 CBETA Online 看到什麼就可以搜得到
    # 所以缺字處理採用預設值，也就是優先使用通用字
    #x2t = CBETA::P5aToText.new(src, dest, gaiji: 'PUA')
    x2t = P5aToText.new(src, dest)
    x2t.convert(args[:arg1])
  end
  
  desc "txt 轉 xml"
  task :t2x => :environment do
    require "tasks/sphinx-t2x"
    c = SphinxT2X.new
    c.convert
  end

  desc "轉出 xml for sphinx search title"
  task :titles => :environment do
    require "tasks/sphinx-titles"
    SphinxTitles.new.run
  end
end