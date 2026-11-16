#!/bin/bash
# RoboPet Mac: start the local server and open the control website.
set -e
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 topilmadi. Mac'da Python 3 o'rnating."
  read -r -p "Enter bosib yoping..."
  exit 1
fi
echo "RoboPet Mac boshqaruv paneli ishga tushmoqda..."
(sleep 1; open "http://localhost:${ROBO_PET_PORT:-8765}") &
python3 mac_server.py
