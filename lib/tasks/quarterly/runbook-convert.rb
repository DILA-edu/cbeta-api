require 'runbook'

module RunbookSectionConvert
  def define_section_convert(config)
    step_creators_list = define_step_creators_list(config)
    step_t4d = define_step_t4d(config)
    step_zip_text = define_step_zip_text(config)

    Runbook.section "Convert (runbook-convert.rb)" do
      if config[:env] != 'staging'
        step '作品內目次 轉為 一部作品一個 JSON 檔 (rake convert:toc)' do
          command 'rake convert:toc'
        end
        step '產生供下載用的 HTML 檔 (rake convert:x2h4d)' do
          command "rake convert:x2h4d[#{config[:publish]}]"
        end
        add step_creators_list
        add step_t4d
        add step_zip_text
      end

      if config[:env] == 'production' # cn 不必做
        step '產生供 DocuSky 使用的 DocuXML 檔 (16分鐘) (rake convert:docusky)' do
          command 'rake convert:docusky'
        end
      end
    end
  end # end of define_section_convert(config)

  def define_step_creators_list(config)
    Runbook.step '含別名的作譯者清單 (rake create:creators)' do
      note '產生 data/all-creators-with-alias.json, 供匯出。'
      note '要從 GitHub 更新 Authority-Databases (如果 Authority ID 有變動，Github 上的 Authority XML 也要請 Authority 管理人員更新)'
      note '要在 rake import:creators 之後執行，才能判斷別名是否出現在作譯者。'
      command 'rake create:creators'
    end
  end

  def define_step_t4d(config)
    Runbook.step '產生供下載用的 Text 檔' do
      note <<~MSG
        讀取 CBETA XML P5a, 每一卷都產生一個 Text 檔, 再壓縮為 zip 檔
        如果有圖檔，也會包在 zip 檔裡。
        整部佛典也包成一個 zip 檔。
        先暫存在 data/text-for-download-tmp, 再移到 public/download/text
      MSG
      command "rake convert:x2t4d[#{config[:publish]}]"
      command "rake convert:x2t4d2[#{config[:publish]}]"
    end
  end

  def define_step_zip_text(config)
    Runbook.step '全部 text 壓縮成一個 zip 檔' do
      ruby_command do |rb_cmd, metadata, run|
        Dir.chdir(config[:download]) do
          system "ln -sf text-for-asia-network cbeta-text"
          system "zip -r -X temp.zip cbeta-text"
          system "mv temp.zip cbeta-text.zip"

          system "zip -r -X temp.zip cbeta-text-with-notes"
          system "mv temp.zip cbeta-text-with-notes.zip"
        end
      end
    end
  end

end # end of module RunbookSectionConvert
