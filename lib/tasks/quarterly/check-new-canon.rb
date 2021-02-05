require 'csv'
require 'set'

puts '--'
print "check new canon..."
$base = ARGV.first

path = File.join($base, 'cbeta-metadata', 'canons.csv')
canons = Set.new
CSV.foreach(path, headers: true) do |row|
  canons << row['id']
end

path = File.join($base, 'cbeta-xml-p5a')
new_canon = []
Dir.entries(path).each do |f|
  next if f.start_with? '.'
  next if f.size > 2
  next if canons.include?(f)
  new_canon << f
end

if new_canon.empty?
  puts "done."
else
  puts "發現新藏經編號：" + new_canon.join(',')
  puts "必須更新 cbeta metadata, 請參考 doc/new-canon.md"
  abort
end