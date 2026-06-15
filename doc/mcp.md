# MCP Server

把 v1 tool surface(目前是 `/v1/tools/find_passages`)包裝成 [MCP](https://modelcontextprotocol.io/)
(Model Context Protocol) Server,讓支援 MCP 的 client(如 Claude)可以直接呼叫 CBETA 全文檢索。

## Endpoint

採用 **Streamable HTTP** transport,單一 endpoint:

```
POST /mcp
```

線上位址(視部署 prefix 而定):

* stable: `https://cbdata.dila.edu.tw/stable/mcp`
* dev: `https://cbdata.dila.edu.tw/dev/mcp`

這是 stateless JSON 模式:每個 `POST` 回傳一個 JSON-RPC response(`application/json`),
不開 SSE stream、不配發 session id。`GET` / `DELETE` 回 `405 Method Not Allowed`。

## 架構

MCP server 是一層薄的 client:收到 `tools/call` 後,把 arguments 原封不動轉成 JSON body
`POST` 給上游的 `/v1/tools/find_passages`,再把回傳的 tool envelope 重新包成 MCP tool result。

```
MCP client ──POST /mcp──▶ McpController ──▶ Mcp::Server ──▶ Mcp::FindPassagesTool
                                                                   │
                                                  Faraday POST /v1/tools/find_passages
                                                                   ▼
                                                            CBETA search 引擎
```

相關檔案:

* `app/controllers/mcp_controller.rb` — transport 層(JSON-RPC over HTTP)
* `app/services/mcp/server.rb` — JSON-RPC 2.0 訊息分派(`initialize` / `tools/list` / `tools/call` / `ping`)
* `app/services/mcp/find_passages_tool.rb` — `find_passages` 工具,呼叫上游 HTTP endpoint
* `app/services/mcp/error.rb` — JSON-RPC 錯誤

## 設定

上游 CBETA API 的 base URL 由環境變數設定:

| 環境變數 | 預設值 | 說明 |
|----------|--------|------|
| `CBETA_API_BASE_URL` | `http://localhost:3000` | MCP server 呼叫 `/v1/tools/find_passages` 的 base URL |

部署在同一台機器時,維持預設(呼叫自己的 `localhost`)即可。

## 提供的工具

### `find_passages`

CBETA 佛典全文檢索。參數與 `/v1/tools/find_passages` 完全一致(input schema 對應
`public/openapi.json` 的 requestBody),必填參數為 `q`。回傳:

* `content`:文字摘要 + 完整結果的 JSON(供只讀 text 的 client)
* `structuredContent`:完整搜尋結果(對應上游回傳的 `data`)
* `isError`:上游回報錯誤或連線失敗時為 `true`

## 連線範例

### 1. initialize

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize",
       "params":{"protocolVersion":"2025-06-18","capabilities":{},
                 "clientInfo":{"name":"demo","version":"0.1"}}}'
```

### 2. tools/list

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

### 3. tools/call

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call",
       "params":{"name":"find_passages","arguments":{"q":"般若波羅蜜","canon":"T","rows":5}}}'
```

### 在 MCP client 設定(remote Streamable HTTP)

以 Claude Code 為例:

```bash
claude mcp add --transport http cbeta https://cbdata.dila.edu.tw/stable/mcp
```

## 測試

```bash
bin/rails test test/services/mcp/server_test.rb test/integration/mcp_test.rb
```
