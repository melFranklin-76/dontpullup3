#!/bin/bash
# Quick performance check script

echo "🔍 Performance Quick Check"
echo "========================="

if [ -f "PERFORMANCE_ANALYSIS.md" ]; then
    echo "✅ Performance analysis document exists"
else
    echo "❌ Performance analysis document missing"
fi

echo ""
echo "📊 Build Configuration Status:"
if grep -q 'SWIFT_OPTIMIZATION_LEVEL = "-O"' dontpullup.xcodeproj/project.pbxproj; then
    echo "✅ Swift optimization enabled"
else
    echo "❌ Swift optimization not enabled"
fi

if grep -q 'DEAD_CODE_STRIPPING = YES' dontpullup.xcodeproj/project.pbxproj; then
    echo "✅ Dead code stripping enabled"
else
    echo "❌ Dead code stripping not enabled"
fi

echo ""
echo "🔧 Optimization Services:"
for service in "PerformanceMonitor" "VideoManager" "FirebaseOptimizer" "LocationViewModel"; do
    if find dontpullup/ -name "*.swift" -exec grep -l "$service" {} \; | head -1 >/dev/null; then
        echo "✅ $service implemented"
    else
        echo "❌ $service not found"
    fi
done

echo ""
echo "Run this script regularly to check optimization status"
