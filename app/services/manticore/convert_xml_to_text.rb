module Manticore
  class ConvertXmlToText
    def self.call(inline_notes:, arg:)
      src = Rails.application.config.cbeta_xml
      dest = inline_notes ? 'with-notes' : 'without-notes'
      dest = Rails.root.join('data', "cbeta-txt-#{dest}-for-manticore")
      puts "dest: #{dest}"

      if arg.nil?
        FileUtils.remove_dir(dest, force: true)
      else
        target_folder = File.join(dest, arg)
        FileUtils.remove_dir(target_folder, force: true)
      end

      # 為了要讓在 CBETA Online 看到什麼就可以搜得到
      # 所以缺字處理採用預設值，也就是優先使用通用字
      x2t = Manticore::P5aToText.new(src, dest, inline_notes:)
      x2t.convert(arg)
    end
  end
end
