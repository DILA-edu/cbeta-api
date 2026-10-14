# frozen_string_literal: true

# 記憶體版的 FirestoreClient,介面相同。
# 寫入時經過真正的 encode → JSON → decode,型別轉換的行為與實際一致。
class FakeFirestore
  attr_reader :docs, :write_count

  def initialize
    @docs = Hash.new { |h, k| h[k] = {} }
    @write_count = 0
  end

  def get(collection, id)
    @docs[collection][id]&.dup
  end

  def list(collection)
    @docs[collection].transform_values(&:dup)
  end

  def query_ids(collection, field, value)
    @docs[collection].select { |_, fields| fields[field] == value }.keys
  end

  def delete_all(deletes)
    deletes.each do |collection, id|
      @docs[collection].delete(id)
      @write_count += 1
    end
  end

  def upsert_all(writes)
    writes.each do |collection, id, fields|
      encoded = JSON.parse(AccountsBackup::FirestoreClient.encode_fields(fields).to_json)
      @docs[collection][id] = AccountsBackup::FirestoreClient.decode_fields(encoded)
      @write_count += 1
    end
  end
end
