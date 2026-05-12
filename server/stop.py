import os
import subprocess
import re

PORT = 8000  # ✅ 종료할 Uvicorn 포트

# 🔍 실행 중인 포트 8000 프로세스 찾기
command = f'netstat -ano | findstr :{PORT}'
result = subprocess.run(command, capture_output=True, text=True, shell=True)

# 🔍 LISTENING 상태인 PID만 추출
pids = set()
for line in result.stdout.splitlines():
    if "LISTENING" in line:
        match = re.search(r'\d+$', line)
        if match:
            pids.add(match.group())

if not pids:
    print("❌ 실행 중인 Uvicorn 프로세스가 없습니다.")
else:
    for pid in pids:
        print(f"🔍 종료할 Uvicorn 프로세스 PID: {pid}")
        os.system(f"taskkill /PID {pid} /F")
        print(f"✅ PID {pid} 종료 완료!")
