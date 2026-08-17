# frozen_string_literal: true

require 'zip'

# 把 { 檔名 => 內容 } 寫成 office 文件的 zip container。
#
# stored 列出的檔名不壓縮 (ODF 規定 mimetype 必須是第一個 entry 且不壓縮),
# 其餘照 entries 的順序寫入。
class OfficeZipWriter
  def self.write(path, entries, stored: [])
    new(path, entries, stored).write
  end

  def initialize(path, entries, stored)
    @path = path
    @entries = entries
    @stored = Array(stored)
  end

  def write
    Zip::OutputStream.open(@path) do |zip|
      @entries.each do |name, content|
        if @stored.include?(name)
          zip.put_next_entry(name, nil, nil, Zip::Entry::STORED)
        else
          zip.put_next_entry(name)
        end
        zip.write(content.to_s.b)
      end
    end
  end
end
