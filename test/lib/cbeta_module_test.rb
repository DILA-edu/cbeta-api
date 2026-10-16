require 'test_helper'
require 'git'
require_relative '../../lib/tasks/cbeta-module'

# cb_xml_updated_at 改成一次 git log 建表, 結果必須與逐檔 @git.log.path(path).first 相同
class CbetaModuleTest < ActiveSupport::TestCase
  class Converter
    include CBETAModule

    def initialize(git) = (@git = git)
  end

  setup do
    @root = Dir.mktmpdir
    git(%w[init -q -b main])
    git(%w[config user.email t@example.com])
    git(%w[config user.name t])
  end

  teardown { FileUtils.rm_rf(@root) }

  def git(args, date: nil)
    env = date ? { 'GIT_AUTHOR_DATE' => date, 'GIT_COMMITTER_DATE' => date } : {}
    out, status = Open3.capture2e(env, 'git', '-C', @root, *args)
    assert status.success?, out
  end

  def commit(files, date)
    files.each do |f, content|
      FileUtils.mkdir_p(File.dirname(File.join(@root, f)))
      File.write(File.join(@root, f), content)
    end
    git(%w[add -A])
    git([ 'commit', '-q', '-m', date ], date:)
  end

  test '與逐檔查詢 ruby-git 的結果相同 (含 merge)' do
    commit({ 'T/T01/T01n0001.xml' => 'a', 'T/T01/T01n0002.xml' => 'a' }, '2026-01-01T10:00:00+08:00')
    git(%w[checkout -q -b side])
    commit({ 'T/T01/T01n0002.xml' => 'side' }, '2026-02-01T10:00:00+08:00')
    git(%w[checkout -q main])
    commit({ 'T/T01/T01n0001.xml' => 'main' }, '2026-03-01T10:00:00+08:00')
    git([ 'merge', '-q', '--no-ff', '-m', 'merge', 'side' ], date: '2026-04-01T10:00:00+08:00')
    # 跨日: UTC 仍是前一天, 本機時區 (+08:00) 已是隔天
    commit({ 'X/X01/X01n0001.xml' => 'x' }, '2026-05-01T23:30:00+00:00')

    repo = Git.open(@root)
    converter = Converter.new(repo)
    paths = %w[T/T01/T01n0001.xml T/T01/T01n0002.xml X/X01/X01n0001.xml]
    paths.each do |path|
      expected = repo.log.path(path).first.date.strftime('%Y-%m-%d')
      assert_equal expected, converter.cb_xml_updated_at(path:), path
      assert_equal expected, converter.cb_xml_updated_at(path: File.join(@root, path)), "絕對路徑 #{path}"
    end
  end

  test '不在 repo 裡的檔案仍然中止' do
    commit({ 'T/T01/T01n0001.xml' => 'a' }, '2026-01-01T10:00:00+08:00')
    converter = Converter.new(Git.open(@root))

    _out, err = capture_io { assert_raises(SystemExit) { converter.cb_xml_updated_at(path: 'T/T01/none.xml') } }
    assert_match(/取得 git log 發生錯誤/, err)
  end
end
