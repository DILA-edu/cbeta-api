require 'nokogiri'

class XMLForDocxToText
  def convert(dir1, dir2)
    @src_base = dir1.to_s
    FileUtils.remove_dir(dir2, true)
    Dir.glob("#{dir1}/**/*.xml").each do |file|
      convert_file(file, dir2)
    end
    puts
  end

  def convert_file(xml_path, dest_base)
    doc = Nokogiri::XML(File.read(xml_path))
    doc.remove_namespaces! # 移除命名空間
    doc.xpath('//footnote').remove
    doc.xpath("//p[@rend='license']").remove

    x = File.dirname(xml_path)
    rel_path = File.dirname(xml_path).delete_prefix(@src_base) # 相對路徑

    # 取得檔案名稱
    file_name = File.basename(xml_path, '.xml')
    dest_folder = File.join(dest_base, rel_path)
    FileUtils.mkdir_p(dest_folder) # 確保目錄存在

    dest_file = File.join(dest_folder, "#{file_name}.txt")

    print "write #{dest_file}    \r"
    body = doc.at_xpath('//body')
    File.write(dest_file, body.text)
  end
end
