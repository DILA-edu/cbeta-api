require 'yaml'
require 'fileutils'
require 'chronic_duration'

class KwicSuffixArray
  def initialize
    @task_base = Rails.root.join('lib', 'tasks')
    compile_cpp
  end

  def build(rel_path)
    t1 = Time.now
    source = File.join(Rails.configuration.x.kwic.temp, rel_path)
    handle_folder(source)
    
    print "sa.rb 花費時間："
    puts ChronicDuration.output(Time.now - t1)
  end

  def call_cpp(path)
    t1 = Time.now
    puts "#{File.basename(__FILE__)}, line: #{__LINE__}, call_cpp, path: #{path}"
    system "#{@task_base}/sa.out #{path}" # 呼叫 c++ 程式
  
    fn = File.join(path, 'sa.dat')
    unless File.exist?(fn)
      abort "呼叫 sa cpp 失敗，#{fn} 不存在"
    end
  
    fn = File.join(path, 'sa-b.dat')
    unless File.exist?(fn)
      abort "呼叫 sa cpp 失敗，#{fn} 不存在"
    end
  
    spend_time = Time.now - t1
    if spend_time > 1
      puts "花費時間：" + ChronicDuration.output(spend_time)
    end
  end
  
  def compile_cpp
    Dir.chdir(@task_base) do
      unless FileUtils.uptodate?('sa.out', ['sa.cpp'])
        puts "compile_cpp"
        # compile c++ program
        cmd = "g++ sa.cpp -std=c++0x -o sa.out"
        puts cmd
        abort unless system(cmd)
        puts "compile_cpp done."
      end
    end
  end
  
  def exist_all_text?(folder)
    p = File.join(folder, 'all.txt')
    File.exist? p
  end
  
  def handle_folder(folder)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(folder, f)
      if exist_all_text?(path)
        call_cpp(path)
      elsif Dir.exist?(path)
        handle_folder(path)
      end
    end
  end
end