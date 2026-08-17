# frozen_string_literal: true

require 'zip'

class XmlToDocxConverter
  # 把 package part 寫成 docx (OPC zip)
  class ZipWriter
    def self.write(path, entries)
      new(path, entries).write
    end

    def initialize(path, entries)
      @path = path
      @entries = entries
    end

    def write
      Zip::OutputStream.open(@path) do |zip|
        @entries.each do |name, content|
          zip.put_next_entry(name)
          zip.write(content.to_s.b)
        end
      end
    end
  end
end
