import os
import subprocess
import re

PORT = 8000  # ✅ translated text Uvicorn text

# 🔍 text text text 8000 translated text text
command = f'netstat -ano | findstr :{PORT}'
result = subprocess.run(command, capture_output=True, text=True, shell=True)

# 🔍 LISTENING statetext PIDtext text
pids = set()
for line in result.stdout.splitlines():
    if "LISTENING" in line:
        match = re.search(r'\d+$', line)
        if match:
            pids.add(match.group())

if not pids:
    print("❌ No running Uvicorn process was found.")
else:
    for pid in pids:
        print(f"🔍 Uvicorn process PID to stop: {pid}")
        os.system(f"taskkill /PID {pid} /F")
        print(f"✅ PID {pid} stopped successfully!")
