module SectionCheck
  def run_section_check
    run_section "檢查作業 (section-check.rb)" do
      step_check_authority
      step_check_p5a
      step_check_gaiji
      step_import_gaiji
    end
  end

  def step_check_authority
    cmd = 'rake check:authority'
    run_step "check authority (#{cmd})" do
      command cmd
    end
  end

  def step_check_p5a
    cmd = 'rake check:p5a'
    run_step "check cbeta xml (#{cmd})" do
      command cmd
    end
  end

  def step_check_gaiji
    run_step '檢查缺字資料' do
      command 'rake check:gaiji'
    end
  end

  def step_import_gaiji
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
