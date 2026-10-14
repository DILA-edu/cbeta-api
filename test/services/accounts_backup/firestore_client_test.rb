# frozen_string_literal: true

require 'test_helper'

class AccountsBackupFirestoreClientTest < ActiveSupport::TestCase
  Client = AccountsBackup::FirestoreClient

  test 'encode 成 Firestore typed value' do
    time = Time.utc(2026, 10, 14, 1, 2, 3, 456_789)
    fields = Client.encode_fields(
      's' => 'x', 'i' => 42, 'b' => false, 'n' => nil, 't' => time
    )

    assert_equal({ stringValue: 'x' }, fields['s'])
    assert_equal({ integerValue: '42' }, fields['i'])
    assert_equal({ booleanValue: false }, fields['b'])
    assert_equal({ nullValue: nil }, fields['n'])
    assert_equal({ timestampValue: '2026-10-14T01:02:03.456789Z' }, fields['t'])
  end

  test 'decode 還原型別,時間保留到微秒' do
    time = Time.utc(2026, 10, 14, 1, 2, 3, 456_789)
    hash = { 's' => 'x', 'i' => 42, 'b' => true, 'n' => nil, 't' => time }
    json = JSON.parse(Client.encode_fields(hash).to_json)

    assert_equal hash, Client.decode_fields(json)
  end

  test '不支援的型別直接報錯,不要默默存成字串' do
    assert_raises(ArgumentError) { Client.encode_value(1.5) }
  end
end
