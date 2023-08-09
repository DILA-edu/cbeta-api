namespace :kwic do
  task build: %w[x2h h2t sa sort_info]

  task :x2h, [:canon] => :environment do |t, args|
    require_relative 'kwic-x2h'
    xml   = Rails.configuration.cbeta_xml
    gaiji = Rails.configuration.cbeta_gaiji
    out   = Rails.configuration.x.kwic.html
    c = P5aToSimpleHTML.new(xml, gaiji, out)
    c.convert(args[:canon])
  end

  task :h2t, [:canon, :vol] => :environment do |t, args|
    require_relative 'kwic-h2t'
    c = KwicHtml2Text.new
    c.convert(args[:canon], args[:vol], true)
    c.convert(args[:canon], args[:vol], false)
  end

  task :sa => :environment do
    require_relative 'kwic-sa'
    KwicSuffixArray.new.build('sa')
    KwicSuffixArray.new.build('sa-without-notes')
  end

  # 只有單卷 index, 不必 sort 了
  # task :sort_info => :environment do
  #   require_relative 'kwic-sort-info'
  #   KwicSortInfo.new.run
  # end

  task :test, [:env] => :environment do |t, args|
    require_relative 'kwic-test'
    KwicTest.new.run(args[:env])
  end

  task :rotate => :environment do
    require_relative 'kwic-rotate'
    KwicRotate.new.run
  end
end
