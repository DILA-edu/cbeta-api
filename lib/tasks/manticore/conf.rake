namespace :manticore do
  desc "create configuration files for manticore"
  task :conf => :environment do
    ManticoreConfig.new.conf
  end
end

class ManticoreConfig
  def initialize
    @base = Rails.configuration.cb.manticore[:conf]
  end

  def conf
    create_conf_for_this_quarter
    merge
  end

  private

  def create_conf_for_this_quarter
    v = Rails.configuration.cb.v
    Rails.configuration.x.se.indexes.each do |index|
      fn = Rails.root.join("lib/tasks/quarterly/manticore-template-#{index}.conf")
      template = File.read(fn)
      s = template % { v: v }
      dest = File.join(@base, "#{v}-#{index}.conf")
      puts "write #{dest}"
      File.write(dest, s)
    end
  end

  def merge
    Dir.chdir(@base) do
      buf = File.read('base.conf') + "\n"
      Dir.glob("[123]-*.conf") do |fn|
        buf << File.read(fn) + "\n"
      end
      File.write("manticore.conf", buf)
    end
  end
end
