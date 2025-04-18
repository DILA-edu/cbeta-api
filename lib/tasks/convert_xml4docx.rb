require 'chronic_duration'
require_relative 'xml4docx1'
require_relative 'xml4docx2'
require_relative 'xml4docx3'

class XMLForDocx
  def convert(publish, canon)
    t1 = Time.now
    xml_root = Rails.application.config.cbeta_xml

    dest1 = Rails.root.join('data', 'xml4docx1')
    
    c = XMLForDocx1.new(xml_root, dest1)
    args = { publish:, canon: }
    c.convert(args)
    
    dest2 = Rails.root.join('data', 'xml4docx2')
    XMLForDocx2.new.convert(dest1, dest2)

    XMLForDocx3.new.check(dest2)

    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  end
  
end
