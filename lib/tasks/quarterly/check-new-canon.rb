require 'csv'
require 'set'
require 'yaml'
require_relative '../cbeta_p5a_share'

include CbetaP5aShare

puts '--'
print "check new canon..."
$base = ARGV.first

path = File.join($base, 'cbeta-metadata', 'canons.yml')
canons = YAML.load_file(path)

path = File.join($base, 'cbeta-xml-p5a')
new_canon = []
each_canon(path) do |c|
  next if canons.key?(c)
  new_canon << c
end

if new_canon.empty?
  puts "done."
else
  puts "發現新藏經編號：" + new_canon.join(',')
  puts "必須更新 cbeta metadata, 請參考 doc/new-canon.md"
  abort
end
