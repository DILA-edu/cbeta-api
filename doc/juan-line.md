# juan-line

先將資料準備在 data/juan-line, 如果資料有更新，可執行以下命令產生新資料：

    rake convert:juanline

或直接從舊版複製

    cp -r /var/www/cbdata6/shared/data/juan-line /var/www/cbdata7/shared/data

然後執行以下命令將資料匯入 RDB：

    rake import:juanline

## 格式

每部佛典一個 JSON 檔 (`data/juan-line/{藏經}/{佛典編號}.json`)，每卷是一個段落陣列，一冊一段。
沒有跨冊的卷只有一段；跨冊的卷 (例如 L1557 第 17 卷由 L130 接到 L131) 依冊序有多段：

```json
{
  "16": [ { "vol": "L130", "lb_begin": "0781b01", "lb_end": "0876a08" } ],
  "17": [ { "vol": "L130", "lb_begin": "0876b01", "lb_end": "0886b12" },
          { "vol": "L131", "lb_begin": "0001a01", "lb_end": "0058b15" } ]
}
```

匯入 RDB 時一段一列，`seq` 從 1 起算；`uuid`、`content_uuid` 只放在 `seq = 1` 那列。
某卷跨過哪些冊可用 `JuanLine.vols(work, juan)` 查詢。

5.18.7 以前的舊格式是每卷一個物件，沒辦法直接匯入 (`import:juanline` 會中止)，
要先用 `rake convert:juanline` 重新產生，不能沿用舊版複製過來的檔案。
