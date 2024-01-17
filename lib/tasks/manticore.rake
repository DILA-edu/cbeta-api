namespace :manticore do
  task :build, [:name] => :environment do |t, args|
    v = Rails.configuration.cb.v
    s = args[:name]
    cmd = "docker exec -it manticore gosu manticore mkdir /var/lib/manticore/r#{v}-#{s}"
    puts cmd
    r = system(cmd)
    puts "exit code: #{r}"
    
    cmd = "docker exec -it manticore gosu manticore indexer #{s}#{v} --rotate"
    puts cmd
    system(cmd)
    puts "exit code: #{r}"
  end
  
  desc "將註解（校註、夾註）轉為 XML 供 Sphinx 建 Index"
  task :notes, [:canon] => :environment do |t, args|
    require_relative 'manticore-notes'
    ManticoreNotes.new.convert(args[:canon])
  end

  desc "XML 轉 txt"
  task :x2t, [:arg1] => :environment do |t, args|
    require_relative 'x2t_for_manticore'

    def convert(inline_notes, arg)
      src = Rails.application.config.cbeta_xml
      dest = inline_notes ? 'with-notes' : 'without-notes'
      dest = Rails.root.join('data', "cbeta-txt-#{dest}-for-manticore")
      puts "dest: #{dest}"
      
      if arg.nil?
        FileUtils.remove_dir(dest, force: true)
      else
        target_folder = File.join(dest, arg)
        FileUtils.remove_dir(target_folder, force: true)
      end
      
      # 為了要讓在 CBETA Online 看到什麼就可以搜得到
      # 所以缺字處理採用預設值，也就是優先使用通用字
      x2t = P5aToText.new(src, dest, inline_notes:)
      x2t.convert(arg)
    end

    convert(true, args[:arg1])
    convert(false, args[:arg1])
  end
  
  desc "txt 轉 xml"
  task :t2x => :environment do
    require "tasks/manticore-t2x"
    c = ManticoreT2X.new
    c.convert
  end

  desc "轉出 xml for manticore search chunks"
  task :chunks => :environment do
    require "tasks/manticore-chunks"
    ManticoreChunks.new.convert
  end

  desc "轉出 xml for manticore search title"
  task :titles => :environment do
    require "tasks/manticore-titles"
    ManticoreTitles.new.run
  end
end
