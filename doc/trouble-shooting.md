# Passenger

passenger-status 命令可以查看狀態

## Memory

如果某個 process 佔用太多 memory, 可以將它移除

    kill <PID>

企業版 Passenger 可以設定 PassengerMemoryLimit 欄位。

## 檢視 active requests

    sudo passenger-status --show=requests

注意 started_at 欄位，如果某個 request 已經執行超過 30秒，那可能就是有問題了。

企業版 Passenger 可以設定 PassengerMaxRequestTime