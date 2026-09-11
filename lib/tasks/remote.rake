namespace :remote do
  desc '測試遠端 API server, 例: rake remote:test[dev], rake remote:test[stable,search]'
  task :test, %i[env part] => :environment do |_t, args|
    ENV['CBETA_XML'] ||= Rails.configuration.cbeta_xml.to_s

    cmd = ['ruby', Rails.root.join('test_remote/run.rb').to_s, args[:env] || 'dev']
    cmd << args[:part] if args[:part].present?
    exec(*cmd)
  end

  desc '全文檢索效能量測, 例: rake remote:bench[dev,stable], ' \
       'rake remote:bench[compare,tmp/bench/a.json,tmp/bench/b.json]'
  task :bench, %i[a b c d] => :environment do |_t, args|
    argv = args.to_a.compact_blank
    argv = %w[dev stable] if argv.empty?
    exec('ruby', Rails.root.join('test_remote/bench.rb').to_s, *argv)
  end
end
