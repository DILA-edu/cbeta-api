namespace :remote do
  desc '測試遠端 API server, 例: rake remote:test[dev], rake remote:test[stable,search]'
  task :test, %i[env part] => :environment do |_t, args|
    ENV['CBETA_XML'] ||= Rails.configuration.cbeta_xml.to_s

    cmd = ['ruby', Rails.root.join('test_remote/run.rb').to_s, args[:env] || 'dev']
    cmd << args[:part] if args[:part].present?
    exec(*cmd)
  end
end
