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

      step '匯入 全部佛典編號 (rake import:work_id)' do
        command 'rake import:work_id'
      end

      # 由 GitHub 上的 cbeta-metadata 匯入，
      # 這要在上一個步驟 work id 都已匯入資料庫之後才能做：
      step '替代佛典 對照表 匯入資料庫 (rake import:alt)' do
        command 'rake import:alt'
      end

      step '匯入 行資訊 (rake import:lines, 約需 22 分鐘)' do
        note '由 XML P5a 匯入行號、該行 HTML、該行註解'
        note '用到此資訊的功能：根據 行首資訊 取得該行文字'
        command 'rake import:lines'
      end

      # 由 GitHub 上的 cbeta-metadata 匯入，
      # 需要: import:alt, import:lines
      step '匯入 部類目錄 (rake import:catelog)' do
        command 'rake import:catalog'
      end

      step '更新「佛典所屬部類」資訊 (rake import:category)' do
        command 'rake import:category'
      end

      step '匯入 佛典資訊 (經名、卷數、title) (rake import:work_info)' do
        # 要從 authority.dila 更新【大正藏】作譯者資料到 GitHub cbeta-metadata.
        #   (參考 2019-08-29 會議記錄)
        confirm <<~MSG
          要先執行 cbeta-metadata/work-info/bin/update-from-authority.rb
          從 authority.dila 《大正藏》作譯者資料 更新到 GitHub cbeta-metadata
        MSG
        command 'rake import:work_info'
      end

      # 這要在 import:work_info 之後做，跨冊的 title 才會對（ex: Y0030)。
      # 由 GitHub 上的 cbeta-metadata 及 p5a 匯入:
      step '匯入「佛典跨冊」資訊 (rake import:cross)' do
        confirm '如果有新增的佛典跨冊，要更新 cbeta-metadata/special-works'
        command 'rake import:cross'
      end

      # 改讀 work-info, 2022-07
      #step '匯入 作譯者 (rake import:creators)' do
      #  command 'rake import:creators'
      #end

      step '匯入地理資訊 (rake import:place)' do
        command 'rake import:place'
      end

      # 改讀 work-info, 2022-07
      #step '匯入時間資訊 (rake import:time)' do
      #  command 'rake import:time'
      #  note '會產生一個全部朝代列表：log/dynasty-all.txt'
      #end

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