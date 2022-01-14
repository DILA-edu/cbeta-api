namespace :kwic do
  task :load => :environment do
    require_relative 'suffix_array_loader'
    SuffixArrayLoader.new.run
  end

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
    c.convert(args[:canon], args[:vol])
  end

  task :sa => :environment do
    require_relative 'kwic-sa'
    KwicSuffixArray.new.build
  end

  task :sort_info => :environment do
    require_relative 'kwic-sort-info'
    KwicSortInfo.new.run
  end

  task :rotate => :environment do
    require_relative 'kwic-rotate'
    KwicRotate.new.run
  end
end
