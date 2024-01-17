module SphinxShare
  def get_info_from_work(work, data=nil, exclude: [])
    data = {} if data.nil?

    w = Work.find_by n: work
    raise "在 works table 裡找不到 #{work}" if w.nil?

    data[:title]     = w.title
    data[:byline]    = w.byline    unless exclude.include?(:byline)
    data[:work_type] = w.work_type unless exclude.include?(:work_type) or w.work_type.nil?

    unless w.time_dynasty.blank?
      d = w.time_dynasty
      data[:dynasty] = @dynasty_labels[d] || d
    end

    data[:time_from]        = w.time_from    unless w.time_from.nil?
    data[:time_to]          = w.time_to      unless w.time_to.nil?
    data[:creators]         = w.creators         unless w.creators_with_id.nil?
    data[:creators_with_id] = w.creators_with_id unless w.creators_with_id.nil?

    data[:category]     = w.category
    data[:category_ids] = w.category_ids
    data[:alt]          = w.juan_list  unless exclude.include?(:alt) or w.alt.nil?
    data[:juan_list]    = w.juan_list  unless exclude.include?(:juan_list)
    data[:juan_start]   = w.juan_start unless exclude.include?(:juan_start)
    
    return data if w.creators_with_id.nil?
    
    a = []
    w.creators_with_id.split(';').each do |creator|
      creator.match(/A(\d{6})/) do
        a << $1.to_i.to_s
      end
    end
    data[:creator_id] = a.join(',')
    
    data
  end

  def read_dynasty_labels
    r = {}
    fn = Rails.root.join('data-static', 'dynasty-order.csv')
    CSV.foreach(fn, headers: true) do |row|
      row['dynasty'].split('/').each do |d|
        r[d] = row['dynasty']
      end
    end
    r
  end
end
