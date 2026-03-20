namespace :manticore do
  desc "create configuration files for manticore"
  task :conf => :environment do
    manticore = Rails.configuration.cb.manticore
    v = Rails.configuration.cb.v
    base = Rails.configuration.x.se.conf

    Rails.configuration.x.se.indexes.each do |index|
      fn = Rails.root.join("lib/tasks/quarterly/manticore-template-#{index}.conf")
      template = File.read(fn)
      s = template % { v: v, manticore: }
      dest = File.join(base, "#{v}-#{index}.conf")
      puts "write #{dest}"
      File.write(dest, s)
    end
  end
end
