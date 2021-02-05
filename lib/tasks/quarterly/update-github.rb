def pull(repo)
  folder = File.join($base, repo)
  puts '--'
  puts "git pull #{folder}"
  Dir.chdir(folder) do
    system('git pull')
  end
end

$base = ARGV.first
pull('Authority-Databases')
pull('cbeta-xml-p5a')
pull('cbeta_gaiji')
pull('cbeta-metadata')
pull('CBR2X-figures') # https://github.com/cbeta-git/CBR2X-figures
pull('kwic25')

if ENV['RAILS_ENV'] != 'cn'
  pull('gaiji-CB') # https://github.com/cbeta-org/gaiji-CB
  pull('ebook-covers') # https://github.com/cbeta-org/ebook-covers
  pull('sd-gif') # https://github.com/cbeta-org/sd-gif
  pull('rj-gif') # https://github.com/cbeta-org/rj-gif
end