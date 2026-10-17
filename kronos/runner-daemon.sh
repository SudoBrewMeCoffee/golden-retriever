#!/bin/bash
# Install the ch-mirror self-hosted GitHub Actions runner as a launchd DAEMON on the runner host
# (macOS), running as the normal user. Run once, after ./config.sh has registered the runner.
#
# Why a daemon and not the runner's own `svc.sh install` (a launchd AGENT): macOS Local Network
# privacy blocks launchd agents from opening connections to LAN hosts such as the Proxmox API,
# while daemons started by launchd are allowed automatically (Apple TN3179). See what-broke #23.
set -euo pipefail
LABEL=actions.runner.grahamhat-ch-mirror.magnus
DIR="$HOME/actions-runner"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
LOGS="$HOME/Library/Logs/$LABEL"
mkdir -p "$LOGS"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true   # remove the agent if svc.sh installed one
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

TMP="$(mktemp)"
cat > "$TMP" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/runsvc.sh</string></array>
  <key>UserName</key><string>$(id -un)</string>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGS/stdout.log</string>
  <key>StandardErrorPath</key><string>$LOGS/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>$HOME</string>
    <key>USER</key><string>$(id -un)</string>
    <key>LOGNAME</key><string>$(id -un)</string>
  </dict>
</dict>
</plist>
PL
sudo install -m 644 -o root -g wheel "$TMP" "$PLIST"
rm -f "$TMP"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
sudo launchctl print "system/$LABEL" | grep -E "state =|pid =" | head -2
