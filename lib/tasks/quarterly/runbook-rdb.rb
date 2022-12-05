require 'runbook'

module RunbookSectionRDB
  def define_section_rdb(config)
    Runbook.section "匯入 RDB (runbook-rdb.rb)" do
      step '匯入 藏經 ID (rake import:canons)' do
        command "rake import:canons"
      end

      step '作品內目次 匯入 TocNode 供搜尋 (rake import:toc)' do
        command 'rake import:toc'
      end

      #step '匯入 全部佛典編號 (rake import:work_id)' do
      #  command 'rake import:work_id'
      #end

      step '匯入 行資訊 (rake import:lines, 約需 22 分鐘)' do
        note '由 XML P5a 匯入行號、該行 HTML、該行註解'
        note '用到此資訊的功能：根據 行首資訊 取得該行文字'
        command 'rake import:lines'
      end

      step '匯入 佛典資訊 (經名、卷數、title) (rake import:work_info)' do
        command 'rake import:work_info'
      end

      # 由 GitHub 上的 cbeta-metadata 匯入，
      # 需要: import:lines, import:work_info
      step '匯入 部類目錄 (rake import:catelog)' do
        command 'rake import:catalog'
      end

      step '匯入 卍續藏 行號對照表 (rake import:lb_maps)' do
        command 'rake import:lb_maps'
      end

      step '匯入 同義詞 (rake import:synonym)' do
        note <<~MSG
          資料來源:
          由 data-static/synonym.txt 匯入
          synonym.txt 來自 CBETA heaven 提供的 fdb_equivalent.txt 
          再經轉檔程式 GoogleDrive/小組雲端硬碟/CBETA專案/階段性任務/2019-05-同義搜尋/同義詞/bin/z2u.rb 將其中的組字式轉為 unicode
        MSG
        command 'rake import:synonym'
      end

      step '更新經號排序 (rake update:sort_order)' do
        confirm '如果 搜尋結果的排序規則 有變動的話，要更新 cbeta gem.'
        command 'rake update:sort_order'
        note '這會 根據 cbeta gem 裡的搜尋排序規則 更新 works, `toc_nodes` table 的 sort_order 欄位.'
      end
    end
  end
end
