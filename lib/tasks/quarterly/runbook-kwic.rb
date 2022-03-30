require 'runbook'

module RunbookSectionKwic
  def define_section_kwic(config)
    Runbook.section "KWIC" do
      step 'suffix array (約11小時)' do
        ruby_command do |rb_cmd, metadata, run|
          system("rake kwic:x2h")
          system("rake kwic:h2t") # simple html => txt, 全部做一次大約花 7 小時
          system("rake kwic:sa")       # suffix array, 約4小時
          note '重排 info.dat, 為了加速讀取 info.dat, 根據 sa 的順序重排 info.dat'
          note '約 1小時46分'
          system("rake kwic:sort_info")
        end
      end

      step '將 suffix array 移至正式資料夾使用' do
        ruby_command do |rb_cmd, metadata, run|
          system("rake kwic:rotate")
        end
      end
    end
  end
end