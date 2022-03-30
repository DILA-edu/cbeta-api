class Work < ActiveRecord::Base
  
  def self.first_file_in_vol(work_id, vol)
    f = XmlFile.where(work: work_id, vol: vol).order(:file).first
    if f.nil?
      CBETA.get_xml_file_from_vol_and_work(vol, work_id)
    else
      f.file
    end
  end
  
  def self.get_info_by_id(work)
    return if work.nil?
    
    if work.is_a? String
      w = Work.find_by n: work
      return if w.nil?
    else
      w = work
    end
    w.to_hash
  end
  
  def self.normalize_no(n)
    n.chomp! '_'
    if n.match(/[a-zA-Z]$/)
      r = n.rjust(5, '0')
    else
      r = n.rjust(4, '0')
    end
    r
  end
  
  def self.normalize_work(n)
    r = n
    # T1969 => T1969A
    unless Work.find_by n: r
      r += 'A' if Work.find_by n: r+'A'
    end
    r
  end
  
  # 本部典籍的第一個 XML 主檔名
  def first_file
    f = XmlFile.where(work: n).order(:file).first
    if f.nil?
      nil
    else
      f.file
    end
  end

  def juan_start
    f = XmlFile.where(work: n).order(:file).first
    if f.nil?
      1
    else
      f.juan_start
    end
  end
  
  def to_hash
    r = {
      work: n,
      uuid: uuid,
      canon: canon,
      category: category,
      orig_category: orig_category,
      vol: vol,
      title: title,
      juan: juan,
      juan_list: juan_list,
      cjk_chars: cjk_chars,
      en_words: en_words
    }
    
    r[:alt] = alt unless alt.nil?
    
    f = first_file
    unless f.nil?
      r[:file] = f
      r[:juan_start] = juan_start
    end
    
    r[:category]      = '' if category.nil?
    r[:orig_category] = '' if orig_category.nil?
    r[:byline]           = byline           unless byline.nil?
    r[:creators]         = creators         unless creators.nil?
    r[:creators_with_id] = creators_with_id unless creators_with_id.nil?
    r[:time_dynasty]     = time_dynasty     unless time_dynasty.nil?
    r[:time_from]        = time_from        unless time_from.nil?
    r[:time_to]          = time_to          unless time_to.nil?
    
    r
  end
  
  def xml_files
    files = XmlFile.where(work: n).order(:file)
    if files.size == 0
      file = {
        file: vol + 'n' + n[1..-1],
        juan_start: 1
      }
      r = [file]
    else
      r = files.map do |item|
        {
          file: item.file,
          juan_start: item.juan_start
        }
      end
    end
    r
  end
end
