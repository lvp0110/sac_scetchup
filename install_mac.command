#!/bin/bash
# Двойной щелчок на Mac: копирует плагин во все установленные SketchUp 2019+.
set -euo pipefail
cd "$(dirname "$0")"
BASE="$HOME/Library/Application Support"
found=0
shopt -s nullglob
for dir in "$BASE"/SketchUp\ 20*; do
  plugins="$dir/SketchUp/Plugins"
  if [ -d "$plugins" ]; then
    rm -rf "$plugins/sac_ease_prep"
    cp sac_ease_prep.rb "$plugins/"
    cp -R sac_ease_prep "$plugins/"
    echo "Установлено: $plugins"
    found=1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "SketchUp 2019 или новее не найден."
  echo "Поставьте плагин вручную: Window → Extension Manager → Install Extension → dist/SAC_EASE.rbz"
  exit 1
fi
echo
echo "Перезапустите SketchUp."
echo "Кнопка: View → Tool Palettes → SAC EASE"
echo "Если SketchUp спросит про неподписанное расширение — разрешите загрузку."
