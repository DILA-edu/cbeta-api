namespace :kwic do
  task :load => :environment do
    require_relative 'suffix_array_loader'
    SuffixArrayLoader.new.run
  end
end
