module SectionCheck
  def run_section_check
    run_section "檢查作業 (section-check.rb)" do
      run_step 'check cbeta xml (rake check:p5）' do
        command 'rake check:p5a'
      end
      
      run_step '檢查缺字資料' do
        command 'rake check:gaiji'
      end
  
      run_step '匯入缺字資料' do
        # 這似乎會將 cb_analytics 也清空
        #unless Rails.env.development?
        #  command 'rake db:schema:load DISABLE_DATABASE_ENVIRONMENT_CHECK=1'
        #end
        command 'rake db:migrate'
        command 'rake import:gaiji'
      end        
    end
  end
end
