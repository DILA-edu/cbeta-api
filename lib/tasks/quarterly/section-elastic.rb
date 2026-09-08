module SectionElastic
  # text index 的 Elasticsearch。
  #
  # 來源是 section_manticore 的 t2x 產出的 text.xml，因此必須排在 manticore section
  # 之後。過渡期內 notes / titles / chunks 仍由 Manticore 提供，見
  # doc/elasticsearch-migration.md。
  def run_section_elastic
    run_section 'Elasticsearch' do
      step_elastic_rebuild
      step_elastic_verify
    end
  end

  def step_elastic_rebuild
    conf = Rails.configuration.x.elasticsearch
    index_name = elastic_index_name

    run_step "建立 index #{index_name} 並切換 alias (約 3 分鐘)" do
      confirm <<~MSG
        index: #{index_name}
        來源:  #{conf.text_xml}
        alias: #{conf.index_alias} (完成後切到新 index)
        位址:  #{conf.url}

        換 index 只靠 alias，不必重啟容器；要退回舊版隨時可以執行
        rake 'elastic:promote[<舊 index 名稱>]'。
      MSG
      command "bundle exec rake 'elastic:rebuild[#{index_name}]'"
      command 'bundle exec rake elastic:info'
    end
  end

  def step_elastic_verify
    run_step '驗證搜尋結果' do
      puts <<~MSG
        與線上 API 比對 golden values（golden 的來源與抓取時間記在
        test/fixtures/files/search_golden.json 的 _meta）：

          bundle exec rake 'elastic:verify_golden[https://cbdata.dila.edu.tw/dev]'

        差異的判讀方式見 doc/elasticsearch-migration.md 的「驗證結果」。
        需要重新抓基準時：
          bundle exec rake 'elastic:fetch_golden[https://cbdata.dila.edu.tw/stable]'
      MSG
      confirm '確認搜尋結果無誤'
    end
  end

  # 例: cbeta_text_2026r3_001。
  # index 名用季號、alias 用角色（cbeta_text_current / cbeta_text_staging），
  # 因此年度輪替時只要重新 promote 一次，見 doc/annual-rotation.md。
  def elastic_index_name
    "cbeta_text_#{Rails.configuration.cb.r.downcase}_001"
  end
end
