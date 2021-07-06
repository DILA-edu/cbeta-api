REPOS = {
  'CBR2X-figures' => 'git@github.com:cbeta-git/CBR2X-figures.git',
  'ebook-covers' => 'git@github.com:cbeta-org/ebook-covers.git',
  'gaiji-CB' => 'git@github.com:cbeta-org/gaiji-CB.git',
  'rj-gif' => 'git@github.com:cbeta-org/rj-gif.git',
  'sd-gif' => 'git@github.com:cbeta-org/sd-gif.git'
}

def pull(repo, tag=nil)
  folder = File.join($base, repo)
  puts '--'
  if Dir.exist?(folder)
    puts "git pull #{folder}"
    Dir.chdir(folder) do
      system('git pull')
      unless tag.nil?
        system("git checkout tags/#{tag}")
      end
    end
  else
    puts "git clone #{folder}"
    Dir.chdir($base) do
      system("git clone #{REPOS[repo]}")
      unless tag.nil?
        system("git checkout tags/#{tag}")
      end
    end
  end
end

$base = ARGV.first
tag = ARGV[1]

pull('Authority-Databases')
pull('cbeta_gaiji')
pull('cbeta-metadata')
pull('CBR2X-figures') # https://github.com/cbeta-git/CBR2X-figures
pull('kwic25')

if ENV['RAILS_ENV'] == 'cn'
  pull('cbeta-xml-p5a', tag)
else
  pull('cbeta-xml-p5a')
  pull('gaiji-CB') # https://github.com/cbeta-org/gaiji-CB
  pull('ebook-covers') # 
  pull('sd-gif') # https://github.com/cbeta-org/sd-gif
  pull('rj-gif') # https://github.com/cbeta-org/rj-gif
end