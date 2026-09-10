module SectionElastic
  # text / notes / titles / chunks 四個 Elasticsearch index。
  #
  # 來源是 section_convert 產出的 data/search-xml/*.xml，
  # 因此必須排在 convert section 之後。見 doc/elasticsearch-migration.md。
  def run_section_elastic
    run_section 'Elasticsearch' do
      step_elastic_rebuild
      step_elastic_vars
      step_elastic_verify
    end
  end

  def step_elastic_rebuild
    conf = Rails.configuration.x.elasticsearch
    release = Rails.configuration.cb.r.downcase

    run_step "建立四個 index (#{release}) 並切換 alias (約 30 分鐘)" do
      confirm <<~MSG
        位址: #{conf.url}

        #{elastic_index_table}

        換 index 只靠 alias，不必重啟容器；要退回舊版隨時可以執行
        rake 'elastic:promote[<種類>,<舊 index 名稱>]'。
      MSG
      command "bundle exec rake 'elastic:rebuild_all[#{release}]'"
      command 'bundle exec rake elastic:info'
    end
  end

  # 異體字表要過濾「CBETA 沒用到的字」，靠 Elasticsearch 的 text index 判斷，
  # 因此必須排在 elastic:rebuild_all 之後 (舊版是查 Manticore，排在 manticore section)。
  def step_elastic_vars
    run_step '匯入 異體字 (rake import:vars)' do
      puts '資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.json'
      puts '過濾條件會查 Elasticsearch 的 text index，所以要排在 index 建好之後。'
      command 'rake import:vars'
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

  private

  # index 名用季號、alias 用角色（cbeta_*_current / cbeta_*_staging），
  # 因此年度輪替時只要重新 promote 一次，見 doc/annual-rotation.md。
  def elastic_index_table
    conf = Rails.configuration.x.elasticsearch
    release = Rails.configuration.cb.r.downcase

    %w[text notes titles chunks].map do |type|
      klass = "CbetaSearch::#{type.camelize}Index".constantize
      format('  %-7s %-32s alias: %-24s 來源: %s',
             type, klass.versioned_index_name(release),
             conf.aliases[type.to_sym], conf.xml[type.to_sym])
    end.join("\n")
  end
end
