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

MCP server 收到 `tools/call` 後,**不走網路**,而是用 Rails 內建的 controller dispatch
機制(`Controller.action(:name).call(env)`,即 router 本身使用的進入點)直接 in-process
呼叫 `V1::ToolsController#find_passages`,完整重用既有的搜尋機制(`init` → `all_in_one`
→ KWIC / facet)與 normalized tool envelope,再把回傳的 envelope 重新包成 MCP tool result。

```
MCP client ──POST /mcp──▶ McpController ──▶ Mcp::Server ──▶ Mcp::FindPassagesTool
                                                                   │
                                       V1::ToolsController.action(:find_passages).call(env)
                                                                   ▼
                                                 SearchController#all_in_one (CBETA search 引擎)
```

因為是同一個 process 內直接 dispatch,所以不需要另外啟動 server、不需要網路連線、
也沒有任何 base URL / 後端位址要設定。

相關檔案:

* `app/controllers/mcp_controller.rb` — transport 層(JSON-RPC over HTTP)
* `app/services/mcp/server.rb` — JSON-RPC 2.0 訊息分派(`initialize` / `tools/list` / `tools/call` / `ping`)
* `app/services/mcp/find_passages_tool.rb` — `find_passages` 工具,in-process 呼叫 `V1::ToolsController`
* `app/services/mcp/error.rb` — JSON-RPC 錯誤

## 提供的工具

### `find_passages`

CBETA 佛典全文檢索。參數與 `/v1/tools/find_passages` 完全一致(input schema 對應
`public/openapi.json` 的 requestBody),必填參數為 `q`。回傳:

* `content`:文字摘要 + 完整結果的 JSON(供只讀 text 的 client)
* `structuredContent`:完整搜尋結果(對應 envelope 的 `data`)
* `isError`:搜尋回報錯誤(如後端搜尋引擎不可用)時為 `true`

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

### Unit / integration tests

```bash
bin/rails test test/services/mcp/server_test.rb test/integration/mcp_test.rb
```

### Smoke test（對 live server）

部署後可用 `bin/smoke_mcp` 對真實 server 跑一輪完整的 smoke test:

```bash
bin/smoke_mcp                                # 預設打 staging (cbdata.dila.edu.tw/dev)
bin/smoke_mcp https://cbdata.dila.edu.tw/stable  # production
bin/smoke_mcp http://localhost:3000              # 本機開發
```

測試項目:

* `initialize` handshake 與 protocol version
* `tools/list` — 確認全部 10 個 tools 都有列出
* `tools/call` happy path — 每個 tool 打一次實際請求,確認 `isError: false`
* validation — 缺必填參數時應回 `isError: true`
* protocol edge cases — notification 回 202、未知 tool 回 -32602、壞 JSON 回 -32700

全部通過時 exit 0,有任何失敗時 exit 1(可直接用在 CI / deploy hook)。
