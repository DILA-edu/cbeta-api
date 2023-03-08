class ImportVisit
  def import
    fn = Rails.root.join('data', 'visits.csv')
    CSV.foreach(fn, headers: true) do |row|
      v = Visit.find_or_create_by(
        url: row['url'], 
        referer: row['referer'],
        accessed_at: row['accessed_at']
      )
      v.update(count: v.count + row['count'].to_i)
    end
  end
end
