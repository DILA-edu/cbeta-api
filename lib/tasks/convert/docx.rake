# frozen_string_literal: true

namespace :convert do
  desc 'xml4docx 轉 docx, 例: rake convert:docx[T01,8]'
  task :docx, %i[filter workers] => :environment do |_t, args|
    t1 = Time.now
    Xml4docxBatchConverter.new(:docx, filter: args[:filter], workers: args[:workers]).convert
    puts ElapsedTime.label(t1)
  end
end
