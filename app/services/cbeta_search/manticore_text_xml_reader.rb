require 'nokogiri'

module CbetaSearch
  # 讀取 Manticore 轉檔流程產出的 data/manticore-xml/text.xml (xmlpipe2 格式)，
  # 逐份 document yield 成 Hash，供 Elasticsearch 匯入。
  #
  # 檔案約 1.3GB，因此不整份載入 DOM，改為逐行累積單一 <sphinx:document> 再解析。
  class ManticoreTextXmlReader
    INTEGER_FIELDS = %w[juan juan_start time_from time_to].freeze
    ARRAY_INTEGER_FIELDS = %w[category_ids creator_id].freeze

    def initialize(path)
      @path = path
      raise CbetaError.new(500), "找不到 text.xml：#{path}" unless File.exist?(path)
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

    def parse_document(xml)
      # Nokogiri 不接受未宣告的 sphinx namespace，去掉前綴後當一般 fragment 解析。
      fragment = Nokogiri::XML.fragment(xml.gsub('sphinx:', ''))
      node = fragment.at_css('document')
      raise CbetaError.new(500), '無法解析 text.xml document' if node.nil?

      doc = { '_id' => node['id'] }
      node.element_children.each do |child|
        doc[child.name] = normalize_value(child.name, child.text)
      end
      doc
    end

    def normalize_value(name, value)
      return value.to_i if INTEGER_FIELDS.include?(name)
      return split_integers(value) if ARRAY_INTEGER_FIELDS.include?(name)

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
