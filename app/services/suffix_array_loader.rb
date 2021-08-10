class SuffixArrayLoader
  def run
    print "將全部單卷 suffix array (含文字) 讀入記憶體..."
    t1 = Time.now
    $global = { sa: {}, text: {} }
    
    sa = File.join(Rails.configuration.kwic_base, 'sa', 'juan')
    Dir.each_child(sa) do |work|
      print "#{work} " if Rails.env.development?
      $global[:sa][work] = {}
      $global[:text][work] = {}
      work_path = File.join(sa, work)
      Dir.each_child(work_path) do |juan|
        juan_path = File.join(work_path, juan)
        j = juan.to_i
        read_files(juan_path, work, j)
      end
    end
    
    puts "done.\n花費時間：" + ChronicDuration.output(Time.now - t1)
  end

  private

  def read_files(src, work, juan)
    $global[:sa][work][juan] = {}
    h = $global[:sa][work][juan]

    fn = File.join(src, 'sa.dat')
    h['f'] = File.read(fn, mode: "rb").unpack("V*")

    fn = File.join(src, 'sa-b.dat')
    h['b'] = File.read(fn, mode: "rb").unpack("V*")

    $global[:text][work][juan] = {}
    h = $global[:text][work][juan]

    fn = File.join(src, 'all.txt')
    h['f'] = File.read(fn, encoding: "UTF-32LE")

    fn = File.join(src, 'all-b.txt')
    h['b'] = File.read(fn, encoding: "UTF-32LE")
  end
end
