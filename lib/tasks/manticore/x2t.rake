namespace :manticore do  
  desc "XML 轉 txt"
  task :x2t, [:arg1] => :environment do |t, args|
    t1 = Time.now
    Manticore::ConvertXmlToText.call(inline_notes: true,  arg: args[:arg1])
    Manticore::ConvertXmlToText.call(inline_notes: false, arg: args[:arg1])
    puts ElapsedTime.label(t1)
  end
end
