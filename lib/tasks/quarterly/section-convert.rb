module SectionConvert
  def run_section_convert
    run_section "Convert (runbook-convert.rb)" do
      run_step '作品內目次 轉為 一部作品一個 JSON 檔 (rake convert:toc)' do
        command 'rake convert:toc'
      end

      run_step '產生供下載用的 HTML 檔 (rake convert:x2h4d)' do
        command "rake convert:x2h4d[#{config[:publish]}]"
      end
      
      step_creators_list
      step_t4d
      step_zip_text

      run_step '產生供 DocuSky 使用的 DocuXML 檔 (16分鐘) (rake convert:docusky)' do
        command 'rake convert:docusky'
      end
    end
  end # end of define_section_convert(config)

  def step_creators_list
    run_step '含別名的作譯者清單 (rake create:creators)' do
      puts '產生 data/all-creators-with-alias.json, 供匯出。'
      puts '要從 GitHub 更新 Authority-Databases (如果 Authority ID 有變動，Github 上的 Authority XML 也要請 Authority 管理人員更新)'
      puts '要在 rake import:creators 之後執行，才能判斷別名是否出現在作譯者。'
      command 'rake create:creators'
    end
  end

  def step_t4d
    run_step '產生供下載用的 Text 檔' do
      puts <<~MSG
        讀取 CBETA XML P5a, 每一卷都產生一個 Text 檔, 再壓縮為 zip 檔
        如果有圖檔，也會包在 zip 檔裡。
        整部佛典也包成一個 zip 檔。
      MSG
      command "rake convert:x2t4d[#{@config[:publish]}]"
      command "rake convert:x2t4d2[#{@config[:publish]}]"
    end
  end

  def step_zip_text
    run_step '全部 text 壓縮成一個 zip 檔' do
      Dir.chdir(@config[:download]) do
        system "ln -sf text-for-asia-network cbeta-text"
        system "zip -r -X temp.zip cbeta-text"
        system "mv temp.zip cbeta-text.zip"

        system "zip -r -X temp.zip cbeta-text-with-notes"
        system "mv temp.zip cbeta-text-with-notes.zip"
      end
    end
  end

end # end of module SectionConvert
