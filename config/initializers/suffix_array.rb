print "將全部 suffix array 讀入記憶體..."
t1 = Time.now
$global = { sa: {}, text: {} }
$global[:sa]['T0001'] = {}

sa = File.join(Rails.configuration.kwic_base, 'sa', 'juan')
Dir.each_child(sa) do |work|
  print "#{work} " if Rails.env.development?
  $global[:sa][work] = {}
  work_path = File.join(sa, work)
  Dir.each_child(work_path) do |juan|
    juan_path = File.join(work_path, juan)
    j = juan.to_i
    $global[:sa][work][j] = {}
    h = $global[:sa][work][j]
    fn = File.join(juan_path, 'sa.dat')
    h['f'] = File.read(fn, mode: "rb").unpack("V*")
    fn = File.join(juan_path, 'sa-b.dat')
    h['b'] = File.read(fn, mode: "rb").unpack("V*")
  end
end

puts "done.\n花費時間：" + ChronicDuration.output(Time.now - t1)