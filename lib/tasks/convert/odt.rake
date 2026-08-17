# frozen_string_literal: true

namespace :convert do
  desc 'xml4docx 轉 odt, 例: rake convert:odt[T01,8]'
  task :odt, %i[filter workers] => :environment do |_t, args|
    t1 = Time.now
    Xml4docxBatchConverter.new(:odt, filter: args[:filter], workers: args[:workers]).convert
    puts ElapsedTime.label(t1)
  end
end
