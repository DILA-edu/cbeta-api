require 'nokogiri'

module CbetaSearch
  # 讀取 rake search_xml:* 產出的 data/search-xml/*.xml，
  # 逐份 document yield 成 Hash，供 Elasticsearch 匯入。
  #
  # 格式是 xmlpipe2 (Sphinx/Manticore 的匯入格式)。Manticore 已退場，
  # 但轉檔流程與格式留了下來，見 doc/elasticsearch-migration.md。
  #
  # text.xml 約 1.3GB、notes.xml 約 2GB，因此不整份載入 DOM，
  # 改為逐行累積單一 <sphinx:document> 再解析。
  class XmlpipeReader
    # 5.2.0 之前這些 XML 放在 data/manticore-xml。server 上的 shared/data 是
    # capistrano 的 linked dir，不會跟著程式改名，所以升級後第一次匯入很可能
    # 撞到這裡 —— 訊息直接告訴對方要 mv，省得去翻部署文件。
    LEGACY_DIR = 'manticore-xml'.freeze

    def initialize(path, integer_fields: [], array_integer_fields: [])
      @path = path
      @integer_fields = integer_fields.to_a
      @array_integer_fields = array_integer_fields.to_a
      raise CbetaError.new(500), missing_source_message(path) unless File.exist?(path)
    end

    def each
      return enum_for(:each) unless block_given?

      buffer = nil
      File.foreach(@path, encoding: 'UTF-8') do |line|
        buffer = +'' if line.include?('<sphinx:document')
        next if buffer.nil?

        buffer << line
        next unless line.include?('</sphinx:document>')

        yield parse_document(buffer)
        buffer = nil
      end
    end

    private

    def missing_source_message(path)
      msg = "找不到匯入來源：#{path}"
      legacy = Pathname.new(path).dirname.dirname.join(LEGACY_DIR)
      return msg unless legacy.directory?

      "#{msg}\n這些 XML 在 5.2.0 由 #{LEGACY_DIR} 改名為 search-xml，" \
        "舊目錄還在 (#{legacy})。請先 mv 過去，見 doc/elasticsearch-deploy.md 的 §4-3。"
    end

    def parse_document(xml)
      # Nokogiri 不接受未宣告的 sphinx namespace，去掉前綴後當一般 fragment 解析。
      fragment = Nokogiri::XML.fragment(xml.gsub('sphinx:', ''))
      node = fragment.at_css('document')
      raise CbetaError.new(500), '無法解析 xmlpipe2 document' if node.nil?

      doc = { '_id' => node['id'] }
      node.element_children.each do |child|
        doc[child.name] = normalize_value(child.name, child.text)
      end
      doc
    end

    def normalize_value(name, value)
      return value.to_i if @integer_fields.include?(name)
      return split_integers(value) if @array_integer_fields.include?(name)

      value
    end

    def split_integers(value)
      value.to_s.split(',').filter_map do |v|
        i = v.strip.to_i
        i unless i.zero?
      end
    end
  end
end
