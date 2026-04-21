module SectionRDB
  def run_section_rdb
    run_section "匯入 RDB (section-rdb.rb)" do
      step_import_canons
      step_import_category
      step_import_toc
      step_import_lines
      step_import_work_info
      step_import_catalog
      step_import_lb_maps
      step_import_synonyms
      step_update_sort_order
      step_import_goto_abbrs
    end
  end

  def step_import_canons
    run_step '匯入 藏經 ID (rake import:canons)' do
      command "rake import:canons"
    end    
  end

  def step_import_catalog
    # 由 GitHub 上的 cbeta-metadata 匯入，
    # 需要: import:lines, import:work_info
    run_step '匯入 部類目錄 (rake import:catalog)' do
      command 'rake import:catalog'
    end    
  end

  def step_import_category
    run_step '匯入 部類 ID (rake import:category)' do
      command "rake import:category"
    end    
  end

  def step_import_goto_abbrs
    run_step '匯入 Goto Abbreviations (rake import:goto_abbrs)' do
      command "rake import:goto_abbrs"
    end    
  end

  def step_import_lines
    run_step '匯入 行資訊 (rake import:lines, 約需 22 分鐘)' do
      puts '由 XML P5a 匯入行號、該行 HTML、該行註解'
      puts '用到此資訊的功能：根據 行首資訊 取得該行文字'
      command 'rake import:lines'
    end    
  end

  def step_import_lb_maps
    run_step '匯入 卍續藏 行號對照表 (rake import:lb_maps)' do
      command 'rake import:lb_maps'
    end    
  end

  def step_import_synonyms
    run_step '匯入 同義詞 (rake import:synonym)' do
      puts <<~MSG
        資料來源:
        由 data-static/synonym.txt 匯入
        synonym.txt 來自 CBETA heaven 提供的 fdb_equivalent.txt 
        再經轉檔程式 GoogleDrive/小組雲端硬碟/CBETA專案/階段性任務/2019-05-同義搜尋/同義詞/bin/z2u.rb 將其中的組字式轉為 unicode
      MSG
      command 'rake import:synonym'
    end    
  end

  def step_import_toc
    run_step '作品內目次 匯入 TocNode 供搜尋 (rake import:toc)' do
      command 'rake import:toc'
    end    
  end

  def step_import_work_info
    run_step '匯入 佛典資訊 (經名、卷數、title) (rake import:work_info)' do
      puts '由 Authority.DILA 及 CBETA XML 取得佛典資訊。'
      command 'rake import:work_info'
      command 'rake check:stat'
    end    
  end

  def step_update_sort_order
    run_step '更新經號排序 (rake update:sort_order)' do
      puts '這會 根據 cbeta gem 裡的搜尋排序規則 更新 works, `toc_nodes` table 的 sort_order 欄位.'
      confirm '如果 搜尋結果的排序規則 有變動的話，要更新 cbeta gem.'
      command 'rake update:sort_order'
    end    
  end
end
