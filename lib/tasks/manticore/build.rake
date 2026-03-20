namespace :manticore do
  task :build, [:name] => :environment do |t, args|
    manticore = Rails.configuration.cb.manticore
    v = Rails.configuration.cb.v
    s = args[:name]

    # 在 container 內 以 manticore 用戶身份 執行命令
    cmd = "docker exec -it #{manticore} gosu manticore mkdir /var/lib/manticore/r#{v}-#{s}"
    puts cmd
    r = system(cmd)
    puts "exit code: #{r}"

    cmd = "sudo chown -R systemd-coredump:systemd-coredump /var/lib/#{manticore}/r#{v}-#{s}"
    puts cmd
    r = system(cmd)
    puts "exit code: #{r}"
    
    cmd = "docker exec -it #{manticore} gosu manticore indexer #{s}#{v} --rotate"
    puts cmd
    system(cmd)
    puts "exit code: #{r}"
  end
end
