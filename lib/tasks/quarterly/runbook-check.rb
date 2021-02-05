require 'runbook'

module Check
  def define_section_check(config)
    Runbook.section "檢查作業 (runbook-check.rb)" do
      if config[:env] != 'staging'
        step 'check cbeta xml (rake check:p5）' do
          command 'rake check:p5a'
        end
        
        step '檢查缺字資料' do
          command 'rake check:gaiji'
        end
      end

      step '匯入缺字資料' do
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