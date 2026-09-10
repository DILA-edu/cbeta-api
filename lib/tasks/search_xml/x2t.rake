namespace :search_xml do  
  desc "XML 轉 txt"
  task :x2t, [:arg1] => :environment do |t, args|
    t1 = Time.now
    SearchXml::ConvertXmlToText.call(inline_notes: true,  arg: args[:arg1])
    SearchXml::ConvertXmlToText.call(inline_notes: false, arg: args[:arg1])
    puts ElapsedTime.label(t1)
  end
end
