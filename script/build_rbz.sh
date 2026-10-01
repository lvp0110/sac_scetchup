#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/SAC_EASE.rbz
zip -r -X dist/SAC_EASE.rbz sac_ease_prep.rb sac_ease_prep -x "*.DS_Store"
echo "dist/SAC_EASE.rbz"
