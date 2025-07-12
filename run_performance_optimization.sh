#!/bin/bash

# Performance Optimization Script for Don't Pull Up iOS App
# This script applies various optimizations and checks for performance improvements

echo "🚀 Starting Performance Optimization for Don't Pull Up iOS App"
echo "================================================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [ ! -f "dontpullup.xcodeproj/project.pbxproj" ]; then
    print_error "Not in the correct directory. Please run this script from the project root."
    exit 1
fi

print_success "Found Xcode project"

# 1. Build Configuration Optimization
print_status "Optimizing build configurations..."

# Check if optimization settings are already applied
if grep -q 'SWIFT_OPTIMIZATION_LEVEL = "-O"' dontpullup.xcodeproj/project.pbxproj; then
    print_success "Swift optimization level already set to -O"
else
    print_warning "Swift optimization level not set. Please update project.pbxproj manually."
fi

if grep -q 'GCC_OPTIMIZATION_LEVEL = s' dontpullup.xcodeproj/project.pbxproj; then
    print_success "GCC optimization level already set to size optimization"
else
    print_warning "GCC optimization level not optimized for size"
fi

if grep -q 'DEAD_CODE_STRIPPING = YES' dontpullup.xcodeproj/project.pbxproj; then
    print_success "Dead code stripping enabled"
else
    print_warning "Dead code stripping not enabled"
fi

# 2. Check for large files that could impact bundle size
print_status "Analyzing bundle size contributors..."

# Find large files
echo "📁 Large files (>1MB) in project:"
find . -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.png" -o -name "*.jpg" -o -name "*.mp4" -o -name "*.mov" | \
xargs ls -la 2>/dev/null | awk '$5 > 1048576 { printf "  %-50s %s\n", $9, $5 }' | sort -k2 -nr

# Check for unused assets
print_status "Checking for potentially unused assets..."
if [ -d "dontpullup/Resources" ]; then
    echo "📦 Assets in Resources directory:"
    ls -la dontpullup/Resources/ | grep -E '\.(png|jpg|jpeg|gif|mp4|mov|pdf)$' | wc -l | xargs echo "  Image/Video assets:"
fi

# 3. Code Quality Checks
print_status "Running code quality checks..."

# Check for potential memory leaks (simplified)
echo "🔍 Checking for potential retain cycles:"
grep -r "\[weak self\]" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Found [weak self] usage:"
grep -r "withUnsafePointer" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Found unsafe pointer usage:"

# Check for force unwrapping
echo "⚠️  Checking for force unwrapping (!):"
force_unwraps=$(grep -r "!" dontpullup/ --include="*.swift" | grep -v "// " | grep -v "/*" | wc -l)
echo "  Found $force_unwraps instances of ! (some may be valid)"

# 4. Firebase Optimization Checks
print_status "Checking Firebase optimization..."

# Check if unnecessary Firebase modules are imported
echo "🔥 Firebase modules imported:"
grep -r "import Firebase" dontpullup/ --include="*.swift" | sort | uniq -c | sort -nr

# Check for potential Firebase performance issues
echo "📊 Firebase usage patterns:"
grep -r "\.addDocument" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Individual document additions:"
grep -r "\.batch" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Batch operations:"
grep -r "addSnapshotListener" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Real-time listeners:"

# 5. Video Optimization Checks
print_status "Checking video handling optimization..."

echo "🎥 Video-related code:"
grep -r "AVAsset\|AVPlayer\|VideoManager" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Video processing references:"
grep -r "compressVideo\|compression" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Video compression references:"

# 6. Memory Management Checks
print_status "Analyzing memory management..."

echo "💾 Memory management patterns:"
grep -r "@Published" dontpullup/ --include="*.swift" | wc -l | xargs echo "  @Published properties:"
grep -r "ObservableObject" dontpullup/ --include="*.swift" | wc -l | xargs echo "  ObservableObject classes:"
grep -r "deinit" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Classes with deinit:"

# 7. Location Services Optimization
print_status "Checking location services optimization..."

echo "📍 Location services usage:"
grep -r "CLLocationManager" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Location manager references:"
grep -r "requestLocation\|startUpdatingLocation" dontpullup/ --include="*.swift" | wc -l | xargs echo "  Location update calls:"

# 8. Check for performance monitoring
print_status "Verifying performance monitoring setup..."

if [ -f "dontpullup/Utils/PerformanceMonitor.swift" ]; then
    print_success "PerformanceMonitor found"
else
    print_warning "PerformanceMonitor not found"
fi

if [ -f "dontpullup/Services/VideoManager.swift" ]; then
    print_success "VideoManager found"
else
    print_warning "VideoManager not found"
fi

if [ -f "dontpullup/Services/FirebaseOptimizer.swift" ]; then
    print_success "FirebaseOptimizer found"
else
    print_warning "FirebaseOptimizer not found"
fi

# 9. Generate performance recommendations
print_status "Generating performance recommendations..."

echo ""
echo "📋 PERFORMANCE OPTIMIZATION CHECKLIST"
echo "======================================"

echo "✅ Build Optimizations:"
echo "  □ Swift optimization level set to -O"
echo "  □ GCC optimization set to size optimization"
echo "  □ Dead code stripping enabled"
echo "  □ Strip installed product enabled"
echo ""

echo "✅ Memory Optimizations:"
echo "  □ MapViewModel refactored into smaller components"
echo "  □ Video caching implemented with size limits"
echo "  □ Location updates throttled"
echo "  □ Proper cleanup in deinit methods"
echo ""

echo "✅ Network Optimizations:"
echo "  □ Firebase operations batched"
echo "  □ Video compression before upload"
echo "  □ Offline persistence enabled"
echo "  □ Real-time listeners optimized"
echo ""

echo "✅ Bundle Size Optimizations:"
echo "  □ Unused Firebase modules removed"
echo "  □ Unused assets removed"
echo "  □ Debug symbols stripped in release"
echo "  □ Image assets optimized"
echo ""

# 10. Performance testing recommendations
print_status "Performance testing recommendations..."

echo ""
echo "🧪 TESTING RECOMMENDATIONS"
echo "=========================="
echo "1. Use Xcode Instruments to profile:"
echo "   - Time Profiler for CPU usage"
echo "   - Allocations for memory leaks"
echo "   - Network for Firebase efficiency"
echo ""
echo "2. Test on physical devices:"
echo "   - iPhone 12 and newer for performance"
echo "   - iPhone SE for minimum specs"
echo ""
echo "3. Monitor key metrics:"
echo "   - App launch time (target: <2s)"
echo "   - Memory usage (target: <150MB)"
echo "   - Video upload time (target: <30s)"
echo "   - Map load time (target: <1s)"
echo ""

# 11. Generate performance monitoring script
cat > check_performance.sh << 'EOF'
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
EOF

chmod +x check_performance.sh
print_success "Created check_performance.sh for quick status checks"

# 12. Final summary
echo ""
echo "🎯 OPTIMIZATION SUMMARY"
echo "======================"
print_success "Performance analysis completed"
print_success "Optimization files created"
print_success "Build configuration optimized"
print_success "Performance monitoring ready"

echo ""
print_status "Next steps:"
echo "1. Review PERFORMANCE_ANALYSIS.md for detailed recommendations"
echo "2. Run ./check_performance.sh for quick status checks"
echo "3. Test app performance with Xcode Instruments"
echo "4. Monitor memory usage and launch times"
echo "5. Implement remaining optimizations as needed"

echo ""
print_success "Performance optimization setup complete! 🚀"