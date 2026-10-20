#!/bin/zsh
# Build release binary and wrap it in AgentUsageBar.app (menu-bar only, no Dock icon).
set -e
cd "$(dirname "$0")"
/usr/bin/swift build -c release
APP=AgentUsageBar.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/AgentUsageBar $APP/Contents/MacOS/
mkdir -p $APP/Contents/Resources && cp icon/AppIcon.icns icon/agy.png $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Agent Usage</string>
<key>CFBundleIdentifier</key><string>app.nabi.agentusagebar</string>
<key>CFBundleExecutable</key><string>AgentUsageBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 0)</string>
<key>NSHumanReadableCopyright</key><string>© 2026 bvnkame</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $PWD/$APP"
