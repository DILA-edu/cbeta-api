class SuffixArrayLoader
  def initialize
    @prefix = Rails.configuration.x.v
  end
  def run
    puts "將全部單卷 suffix array (含文字) 讀入記憶體..."
    puts "Version: #{@prefix}"
    t1 = Time.now
    
    sa = File.join(Rails.configuration.kwic_base, 'sa', 'juan')
    Dir.entries(sa).sort.each do |work|
      next if work.start_with?('.')
      print " #{work}"
      work_path = File.join(sa, work)
      Dir.each_child(work_path) do |juan|
        juan_path = File.join(work_path, juan)
        j = juan.to_i
        read_files(juan_path, work, j)
      end
    end
    
    puts "\n讀取 suffix array 完成，花費時間：" + ChronicDuration.output(Time.now - t1)
  end

  private

  def read_files(src, work, juan)
    k = "#{@prefix}/sa/#{work}/#{juan}"

    Rails.cache.fetch("#{k}/f") do
      fn = File.join(src, 'sa.dat')
      File.read(fn, mode: "rb").unpack("V*")
    end

    Rails.cache.fetch("#{k}/b") do
      fn = File.join(src, 'sa-b.dat')
      File.read(fn, mode: "rb").unpack("V*")
    end

    k = "/text/#{work}/#{juan}"

    Rails.cache.fetch("#{k}/f") do
      fn = File.join(src, 'all.txt')
      File.read(fn, encoding: "UTF-32LE")
    end

    Rails.cache.fetch("#{k}/b") do
      fn = File.join(src, 'all-b.txt')
      File.read(fn, encoding: "UTF-32LE")
    end
  end
end
