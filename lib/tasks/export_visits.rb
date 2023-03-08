class ExportVisit
  def export(d1, d2)
    count = 0
    output_string = CSV.generate do |csv|
      csv << %w[url accessed_at count referer]
      rows = Visit.where("accessed_at BETWEEN ? AND ? ", d1, d2)
      count += rows.size
      rows.each do |v|
        csv << [v.url, v.accessed_at, v.count, v.referer]
      end
    end
    
    fn = Rails.root.join('data', 'visits.csv')
    puts "資料筆數： #{count}"
    puts "write #{fn}"
    File.write(fn, output_string)
  end
end
