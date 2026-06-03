namespace :manticore do
  desc "create configuration files for manticore"
  task :conf => :environment do
    v = Rails.configuration.cb.v
    base = Rails.configuration.cb.manticore.conf

    Rails.configuration.x.se.indexes.each do |index|
      fn = Rails.root.join("lib/tasks/quarterly/manticore-template-#{index}.conf")
      template = File.read(fn)
      s = template % { v: v }
      dest = File.join(base, "#{v}-#{index}.conf")
      puts "write #{dest}"
      File.write(dest, s)
    end
  end
end
