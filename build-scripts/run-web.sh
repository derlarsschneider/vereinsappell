#!/bin/bash -e

flutter run -d chrome \
  --web-port=8080 \
  --web-browser-flag="--new-window" \
  --web-browser-flag="--user-data-dir=/tmp/chrome_test2" \
  --web-browser-flag="--enable-unsafe-swiftshader" \
  --web-browser-flag="--disable-software-rasterizer" \
  --web-browser-flag="--enable-gpu-rasterization" \
  --web-browser-flag="--enable-hardware-overlays" \
  --web-browser-flag="--auto-open-devtools-for-tabs"
