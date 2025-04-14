require_relative 'cbeta_p5a_share'

class CheckAuthority

  def initialize
    @authority = AuthorityService.new
    @authority.read_catalog
    @authority.read_persons
  end
  
  def check
    @errors = ''

    @authority.catalog.each do |work_id, work|
      next unless work.key?('contributors')
      work['contributors'].each do |contributor|
        id = contributor['id']
        next if id.nil?
        unless @authority.persons.key?(id)
          @errors << "Catalog Authority #{work_id} contributor id #{id} 在 Person Authority 中不存在\n"
        end
      end
    end

    if @errors.empty?
      puts "檢查 Authority 成功，無錯誤。".green
    else
      puts @errors.red
    end
  end
end
