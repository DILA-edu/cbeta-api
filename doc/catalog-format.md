# CBETA Catalog 共用格式

CBReader 與 CBETA API 共用的目錄，由 heaven 於 GitHub 提供：

- 部類目錄：<https://github.com/heavenchou/cbwork-bin/blob/master/cbreader2X/bulei/bulei.txt>
- 分冊目錄（原書目錄）：<https://github.com/heavenchou/cbwork-bin/blob/master/cbreader2X/nav/advance_nav.txt>

CBETA API 以 `rake import:catalog` 匯入（`lib/tasks/import/catalog.rake`），
匯入時直接讀取 GitHub 上 master branch 當下的內容。

## Tree Node

純文字，每一行表示 tree 的一個 node 或多個 node（例如冊號、範圍會展開成多部佛典）。

## Level

行首 tab 數量表示 level。

## Internal Node

如果 node 有 children，那麼整行都是描述性文字標籤 (node label)，不當作連結目標。

例：bulei.txt, line 1

```
01 阿含部類 T01-02,25,33 etc.
```

### 對照：`(=...)`

label 以「佛典編號 `(=對照清單)` 名稱」開頭時，表示這部佛典的內容對應到其他佛典，
children 逐一列出對應的佛典。

| 寫法 | 意義 |
|---|---|
| `X0002 (=T0320) 父子合集經` | CBETA 未收錄此經全文，內容見 children 列出的佛典 |
| `JB214 (=X0615+T1939+...+選錄) 蕅益大師佛學十種` | 對照清單含「選錄」：CBETA 收錄其中一部分，children 裡會有該佛典本身 |

例：advance_nav.txt

```
JB214 (=X0615+T1939+X0974+X1137+X60n1123_p0540a16+X1124+X0703+T1500+選錄) 蕅益大師佛學十種
	X0615 法華經綸貫
	...
	X60n1123_p0540a16 X1123 在家律要廣集 (卷3) 〈梵網經懺悔行法〉
	...
	JB214 蕅益大師佛學十種（選錄「性學開蒙」．「梵室偶談」兩種）
```

對照清單只是說明，連結目標以 children 為準。

## Leaf Node

如果 node 沒有 children，那就是「佛典或文件」，大概有這些格式：

| 名稱 | 範例 | 說明 |
|---|---|---|
| 藏經代碼 | `L` | 把 L 整部藏的佛典都列出來 |
| 冊號 | `T10` | T10 的全部佛典都列出來 |
| 冊號範圍 | `T05..T07` | 兩個半形句點表示範圍，T05 到 T07 的全部佛典都列出來 |
| 佛典編號 | `T0001 長阿含經` | 第一個半形空格分隔為兩欄。第一欄是佛典編號 (work id)；後面的經名、譯者只是參考用 |
| 佛典編號列舉 | `T0099,T0100` | 半形逗點區隔佛典編號 |
| 佛典編號範圍 | `T0262..T0277` | 兩個半形句點表示範圍，T0262 到 T0277 全部列出來 |
| 單卷 | `T0220_576 T0220 (卷576) 大般若經第八會那伽室利分` | 第一個半形空格分隔為兩欄。第一欄：底線分隔 work id + 卷號；第二欄：node label |
| 卷範圍 | `T0310_017..018 T0310 (卷17-18) 大寶積經無量壽如來會第五` | 第一個半形空格分隔為兩欄。第一欄：底線分隔 work id + 卷號範圍；第二欄：node label。全文檢索搜尋「淨土宗部類」時，這二卷也要算進去 |
| 指定行首 | `T09n0262_p0056c02 T0262 妙法蓮華經 (卷7) 〈妙法蓮華經觀世音菩薩普門品〉` | 第一個半形空格分隔為兩欄。第一欄：行首資訊；第二欄：node label |
| HTML 文件 | `help/other/N/main_menu/N01.htm 第一冊` | 第一個半形空格分隔為兩欄。第一欄是 HTML 檔案路徑；第二欄是 node label |

「指定行首」的 label 慣例：卷號放在半形括號裡 `(卷7)`，品名或篇名放在 `〈〉` 裡。

## Note

部類目錄 bulei.txt 要注意：單卷或多卷，要檢查所屬部類和原經是否相同。例如：

- `T0220_579..583` 目前在般若部類，而 T0220 原本就是般若部類，不用額外處理。
- `T0310_017..018` 在淨土宗部類，而 T0310 是在寶積部類，這就要額外處理。

## CBETA API 的處理方式

以下是 CBETA API 匯入時另外做的事，CBReader 不必遵守。

### node_type

`/catalog_entry` 回傳的 `node_type`：

| 值 | 來源 |
|---|---|
| `work` | leaf 的佛典、單卷、卷範圍、指定行首 |
| `alt` | internal node 的 label 含 `(=` 又不含 `+選錄`；或 leaf 佛典依 metadata 展開對照 (見下節) |
| `html` | HTML 文件 |
| 無 | 其他 internal node |

### leaf 佛典的對照展開

leaf 佛典若在 metadata 有對照（`works.alt`，例如 X0002 → T0320），API 會依 metadata 把它展開成 `alt` 節點，
底下列出對應的佛典，讓沒有全文的佛典仍可連到內容。

對照清單含有佛典本身的（例如 JB214 的 `works.alt` 為 `X0615+...+JB214`），
表示 CBETA 有收錄其中一部分（選錄），API 視為一般佛典節點，不展開。
