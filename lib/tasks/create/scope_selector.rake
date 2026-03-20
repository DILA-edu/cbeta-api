namespace :create do
  desc "產生 供 UI 使用的 範圍選擇清單"
  task :scope_selector => :environment do
    CreateScopeSelector.new.create
  end
end

class CreateScopeSelector
  def initialize
    @dest = Rails.configuration.cb.sc
    FileUtils.makedirs(@dest)
  end

  def create
    create_scope_selector_by_category
    create_scope_selector_by_vol
  end

  private

  def create_scope_selector_by_category
    puts "create scope selector by category"
    children = []
    r = [
      {
        title: "選擇全部",
        key: "root",
        children: children
      }
    ]
    add_catalog_entries('CBETA', children)
    
    fn = File.join(@dest, "category.json")
    puts "write #{fn}"
    File.write(fn, JSON.pretty_generate(r))
  end

  def create_scope_selector_by_vol
    puts "create scope selector by vol"
    @canons = CBETA::Canon.new
    children = []
    r = [
      {
        title: "選擇全部",
        key: "root",
        children: children
      }
    ]

    CBETA::SORT_ORDER.each do |canon|
      selector_add_canon(canon, children)
    end

    fn = File.join(@dest, "vol.json")
    puts "write #{fn}"
    File.write(fn, JSON.pretty_generate(r))
  end

  def add_catalog_entries(id, dest)
    CatalogEntry.where(parent: id).order(:n).each do |ce|
      if ce.node_type == 'work'
        info = Work.get_info_by_id(ce.work)
        abort "Work 資料庫找不到：#{ce.work}, catalog_entry: #{ce.n}" if info.nil?
        title = "#{ce.work} #{info[:title]} (#{info[:juan]}卷)"
        unless info[:byline].blank?
          title += "【#{info[:byline]}】"
        end
        dest << { 
          title: title,
          key: ce.work
        }
      elsif ce.node_type != 'html'
        children = []
        add_catalog_entries(ce.n, children)
        unless children.empty?
          dest << { 
            title: ce.label,
            children: children
          }
        end
      end
    end
  end

  def selector_add_canon(canon, dest)
    children = []
    d = { 
      title: @canons.get_canon_attr(canon, 'chinese_name'),
      children: children
    }
    id = "orig-#{canon}"
    add_catalog_entries(id, children)
    dest << d
  end
end
