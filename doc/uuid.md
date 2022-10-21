# UUID

供 Asia Network 使用
Resource Provider API 說明：<https://rise.mpiwg-berlin.mpg.de/pages/doc_for_resource_providers>

1. 先準備好 data/juan-line

    bundle exec rake convert:juanline

上面的 juan-line 在產生各卷的 UUID 時要用到。

2. 產生 UUID, 在 local 端執行

    bundle exec rake import:work_info
    bundle exec rake create:uuid

以上命令會產生 JSON 格式的 uuid 放在 data-static/uuid 資料夾裡
之前產生過的，會維持舊的。

UUID 應該儘量維持不變，第一次產生之後就沿用。

data-static 資料夾也要上傳 git.
