#!/usr/bin/env bash

echo "Testing dependency checker..."
export CURSOR_CHANGED_FILES="Views/IncidentTypePicker.swift"
python3 .cursor/dependency_inspector.py --config dependencies.json
if [ $? -eq 0 ]; then echo "✅ No missing deps"; else echo "❌ Missing deps"; fi

echo -e "\nTesting with a known issue..."
export CURSOR_CHANGED_FILES="Views/MapView.swift"
TEMP=$(mktemp --suffix=".swift")
cat > $TEMP << 'EOF'
import MapKit
struct T { func test(){ let v = MKUserLocationView(annotation: x, reuseIdentifier: "id"); v?.tintColor=UIColor.red } }
EOF
python3 .cursor/dependency_inspector.py --config dependencies.json $TEMP
if [ $? -eq 1 ]; then echo "✅ Issue detected"; else echo "❌ Issue not detected"; fi
rm -f $TEMP
echo -e "\nTests complete." 