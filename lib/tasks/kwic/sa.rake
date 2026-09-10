namespace :kwic do
  task :sa => :environment do
    t1 = Time.now
    KwicSuffixArray.new.build('sa')
    KwicSuffixArray.new.build('sa-without-notes')
    puts ElapsedTime.label(t1)
  end
end

class KwicSuffixArray
  def initialize
    @task_base = Rails.root.join('lib', 'tasks')
    compile_cpp
  end

  def build(rel_path)
    t1 = Time.now
    puts "\n建立 suffix array: #{rel_path}"
    @juan_count = 0
    source = File.join(Rails.configuration.x.kwic.temp, rel_path)
    handle_folder(source)
    puts # 結束進度行
    puts "#{rel_path}: #{@juan_count} 卷, #{ElapsedTime.label(t1)}"
  end

  def call_cpp(path)
    system "#{@task_base}/sa.out #{path}" # 呼叫 c++ 程式

    fn = File.join(path, 'sa.dat')
    unless File.exist?(fn)
      abort "\n呼叫 sa cpp 失敗，#{fn} 不存在"
    end

    fn = File.join(path, 'sa-b.dat')
    unless File.exist?(fn)
      abort "\n呼叫 sa cpp 失敗，#{fn} 不存在"
    end

    # 卷數很多，每 100 卷更新同一行進度即可
    @juan_count += 1
    print "\r  已完成 #{@juan_count} 卷" if (@juan_count % 100).zero?
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
