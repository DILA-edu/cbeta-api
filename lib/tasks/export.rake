namespace :export do  
  desc "匯出存取紀錄"
  task :visits, [:d1,:d2] => :environment do |t, args|
    require "tasks/export_visits"
    exporter = ExportVisit.new
    exporter.export args[:d1], args[:d2]
  end
end
