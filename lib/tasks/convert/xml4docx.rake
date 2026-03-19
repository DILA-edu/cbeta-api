namespace :convert do
  desc "XML 轉 xml4docx 格式 (用來轉 docx)"
  task :xml4docx => :environment do
    month = Date.today.strftime('%Y-%m')
    puts "xml4docx1"
    Rake::Task["convert:xml4docx1"].invoke(month, 'T')
    puts "xml4docx2"
    Rake::Task["convert:xml4docx2"].invoke('T')
    puts "check:xml4docx"
    Rake::Task["check:xml4docx"].invoke
  end
end
