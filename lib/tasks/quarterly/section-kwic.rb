module SectionKwic
  def run_section_kwic
    run_section "KWIC" do
      run_step 'suffix array (約11小時)' do
        command "rake kwic:x2h"
        command "rake kwic:h2t" # simple html => txt, 全部做一次大約花 7 小時
        command "rake kwic:sa"       # suffix array, 約4小時
        
        # 只有單卷 index, 不必 sort 了
        # puts '重排 info.dat, 為了加速讀取 info.dat, 根據 sa 的順序重排 info.dat'
        # puts '約 1小時46分'
        # command "rake kwic:sort_info"
      end

      run_step '將 suffix array 移至正式資料夾使用' do
        command "rake kwic:rotate"
      end
    end
  end
end
