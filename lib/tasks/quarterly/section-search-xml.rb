# 產生全文檢索用的 XML，輸出到 data/search-xml。
#
# 檔案格式仍是 xmlpipe2 (Sphinx/Manticore 的匯入格式)，
# 由 CbetaSearch::XmlpipeReader 解析後送進 Elasticsearch。
# Manticore 已於 2026-09 全面退場，見 doc/elasticsearch-migration.md。
module SectionSearchXml
  def run_section_search_xml
    run_section '全文檢索 XML (xmlpipe2)' do
      step_search_xml_x2t
      step_search_xml_t2x
    end
  end

  def step_search_xml_t2x
    run_step '轉出全文檢索所需的 xml' do
      confirm <<~MSG
      需要部類、時間資訊，要執行過：
        rake import:category
        rake import:time
      MSG

      t1 = Time.now

      command 'rake search_xml:t2x'
      command 'rake search_xml:notes'
      command 'rake search_xml:titles'
      command 'rake search_xml:chunks'

      print "step_search_xml_t2x "
      puts ElapsedTime.label(t1)
    end
  end

  def step_search_xml_x2t
    cmd = "rake search_xml:x2t"
    run_step "先把 XML P5a 轉為 text (#{cmd})" do
      command cmd
    end
  end
end # end of module
