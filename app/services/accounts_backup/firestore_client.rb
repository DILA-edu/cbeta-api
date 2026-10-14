# frozen_string_literal: true

require 'googleauth'

module AccountsBackup
  # Firestore REST API 的最小 client: 只做備份需要的讀單筆、列 collection、
  # 單一欄位查詢、批次 upsert 與刪除。
  #
  # 為什麼不用 google-cloud-firestore gem: 它依賴 grpc native extension,
  # 新版 Ruby 常常沒有預編譯版本,在 server 上要自己 build;而備份的資料量很小,
  # REST 完全夠用。
  #
  # 對外介面只吃/吐一般的 Ruby Hash(值為 String / Integer / true / false /
  # nil / Time),Firestore 的 typed value 編碼只在這個 class 裡處理。
  # 這也讓 Sync / Restore 的測試可以換成記憶體版的 fake client。
  class FirestoreClient
    BASE_URL = 'https://firestore.googleapis.com/v1'
    SCOPE = 'https://www.googleapis.com/auth/datastore'

    # Firestore 單次 commit 最多 500 個 write
    MAX_WRITES_PER_COMMIT = 500
    PAGE_SIZE = 300

    class Error < StandardError; end

    def self.from_config(config)
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(config.credentials), scope: SCOPE
      )
      new(project_id: config.project_id, database_id: config.database_id, credentials:)
    end

    def initialize(project_id:, database_id:, credentials:)
      @database = "projects/#{project_id}/databases/#{database_id}"
      @credentials = credentials
      @http = Faraday.new(url: BASE_URL, request: { timeout: 30, open_timeout: 10 }) do |f|
        f.request :json
        f.response :json
      end
    end

    # 回傳 fields Hash;文件不存在回 nil
    def get(collection, id)
      response = request(:get, document_path(collection, id))
      return nil if response.status == 404

      check!(response)
      self.class.decode_fields(response.body['fields'])
    end

    # 回傳 { id => fields } (整個 collection)
    def list(collection)
      docs = {}
      page_token = nil
      loop do
        params = { pageSize: PAGE_SIZE, pageToken: page_token }.compact
        response = check!(request(:get, "#{@database}/documents/#{collection}", params:))
        Array(response.body['documents']).each do |doc|
          docs[doc['name'].split('/').last] = self.class.decode_fields(doc['fields'])
        end
        page_token = response.body['nextPageToken']
        break if page_token.blank?
      end
      docs
    end

    # writes: [[collection, id, fields], ...],整筆覆寫 (upsert)。
    # 每 500 筆一個 commit;單一 commit 內是 atomic,跨 commit 不是 ——
    # 呼叫端要讓重跑是安全的 (Sync 是 upsert + 最後才推進 watermark)。
    def upsert_all(writes)
      writes.each_slice(MAX_WRITES_PER_COMMIT) do |slice|
        body = {
          writes: slice.map do |collection, id, fields|
            { update: { name: document_path(collection, id), fields: self.class.encode_fields(fields) } }
          end
        }
        check!(request(:post, "#{@database}/documents:commit", body:))
      end
    end

    # 回傳 collection 中 field == value 的文件 id
    def query_ids(collection, field, value)
      body = {
        structuredQuery: {
          from: [ { collectionId: collection } ],
          where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: self.class.encode_value(value) } },
          select: { fields: [ { fieldPath: '__name__' } ] }
        }
      }
      response = check!(request(:post, "#{@database}/documents:runQuery", body:))
      # 回應是陣列;沒有結果時只有一個不含 document 的元素 (只有 readTime)
      Array(response.body).filter_map { |item| item.dig('document', 'name')&.split('/')&.last }
    end

    # deletes: [[collection, id], ...]。刪不存在的文件不會報錯。
    def delete_all(deletes)
      deletes.each_slice(MAX_WRITES_PER_COMMIT) do |slice|
        body = { writes: slice.map { |collection, id| { delete: document_path(collection, id) } } }
        check!(request(:post, "#{@database}/documents:commit", body:))
      end
    end

    def self.encode_fields(hash)
      hash.to_h { |k, v| [ k.to_s, encode_value(v) ] }
    end

    def self.encode_value(value)
      case value
      when nil then { nullValue: nil }
      when true, false then { booleanValue: value }
      when Integer then { integerValue: value.to_s }
      when Time, ActiveSupport::TimeWithZone, DateTime
        { timestampValue: value.utc.iso8601(6) }
      when String then { stringValue: value }
      else raise ArgumentError, "不支援的型別: #{value.class}"
      end
    end

    def self.decode_fields(fields)
      (fields || {}).to_h { |k, v| [ k, decode_value(v) ] }
    end

    def self.decode_value(value)
      type, raw = value.first
      case type
      when 'nullValue' then nil
      when 'booleanValue' then raw
      when 'integerValue' then raw.to_i
      when 'timestampValue' then Time.iso8601(raw)
      when 'stringValue' then raw
      else raise ArgumentError, "不支援的 Firestore 型別: #{type}"
      end
    end

    private

    def document_path(collection, id)
      "#{@database}/documents/#{collection}/#{id}"
    end

    def request(method, path, params: nil, body: nil)
      @http.run_request(method, path, body, auth_headers) do |req|
        req.params.update(params) if params
      end
    rescue Faraday::Error => e
      raise Error, "Firestore 連線失敗: #{e.class}: #{e.message}"
    end

    # apply 會在 token 過期時自動重新取得
    def auth_headers
      @credentials.apply({})
    end

    def check!(response)
      return response if response.success?

      message = response.body.is_a?(Hash) ? response.body.dig('error', 'message') : response.body
      raise Error, "Firestore HTTP #{response.status}: #{message}"
    end
  end
end
