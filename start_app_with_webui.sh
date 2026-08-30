#!/bin/bash

# Start both the web-ui server and Flutter app

echo "Starting browser-use web-ui server..."
cd web-ui
source .venv/bin/activate
python webui.py --ip 127.0.0.1 --port 7788 &
WEBUI_PID=$!

# Wait for web-ui to start
echo "Waiting for web-ui to start..."
sleep 5

# Check if web-ui is running
if curl -s http://127.0.0.1:7788 > /dev/null; then
    echo "✓ web-ui is running on http://127.0.0.1:7788"
else
    echo "✗ web-ui failed to start"
    exit 1
fi

# Start Flutter app
echo "Starting Flutter app..."
cd ..
flutter run

# Cleanup
echo "Stopping web-ui server..."
kill $WEBUI_PID