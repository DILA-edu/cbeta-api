module SectionKwic
  def run_section_kwic
    run_section "KWIC" do
      run_step 'suffix array (約11小時)' do
        t1 = Time.now
        
        command "rake kwic:x2h"
        command "rake kwic:h2t" # simple html => txt, 全部做一次大約花 7 小時
        command "rake kwic:sa"       # suffix array, 約4小時
        
        puts "step_kwic_suffix_array 完成時間: #{Time.now}"
        ElapsedTime.label(t1)
      end

      run_step '將 suffix array 移至正式資料夾使用' do
        command "rake kwic:rotate"
      end
    end
  end
end
