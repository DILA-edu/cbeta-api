module SectionKwic
  def run_section_kwic
    run_section "KWIC" do
      run_step 'suffix array (約1.5小時)' do
        t1 = Time.now
        
        command "rake kwic:x2h"
        command "rake kwic:h2t" # simple html => txt
        command "rake kwic:sa"       # suffix array
        # 以上三步合計約 1.5 小時（2026-09 實測 1 小時 11 分）
        
        puts "suffix array 完成時間: #{Time.now}"
        puts ElapsedTime.label(t1)
      end

      run_step '將 suffix array 移至正式資料夾使用' do
        command "rake kwic:rotate"
      end
    end
  end
end
