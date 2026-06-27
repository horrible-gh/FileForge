$port = 8000
$processes = netstat -ano | Select-String ":$port" | Where-Object { $_ -match "LISTENING" } | ForEach-Object { ($_ -split "\s+")[-1] }

if ($processes) {
    foreach ($proc_id in $processes) {  # ✅ `$pid` → `$proc_id`로 변경
        Write-Host "🔍 종료할 Uvicorn 프로세스 PID: $proc_id"
        Stop-Process -Id $proc_id -Force -ErrorAction SilentlyContinue
        Write-Host "✅ PID $proc_id 종료 완료!"
    }
} else {
    Write-Host "❌ 실행 중인 Uvicorn 프로세스가 없습니다."
}
