#!/bin/bash
# Sends a native OS notification when Claude needs user input.
# Used as a Notification hook.
# Supports macOS (osascript), Linux (notify-send), and WSL (powershell).

cat >/dev/null 2>&1

# Fixed literals only below: the hook's stdin is untrusted and must never reach a notifier.
MESSAGE="Claude Code needs your attention"
TITLE="Claude Code"

# Test/dry-run mode: print instead of notifying (used by hook fixtures).
if [ "${TOOLKIT_NOTIFY_DRYRUN:-0}" = "1" ]; then
  echo "notify: $TITLE: $MESSAGE"
  exit 0
fi

# macOS
if command -v osascript >/dev/null 2>&1; then
  osascript -e 'on run {msg, ttl}' -e 'display notification msg with title ttl' -e 'end run' -- "$MESSAGE" "$TITLE" 2>/dev/null
  exit 0
fi

# Linux (native)
if command -v notify-send >/dev/null 2>&1; then
  notify-send -- "$TITLE" "$MESSAGE" 2>/dev/null
  exit 0
fi

# WSL → Windows toast
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -Command '[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null; $n = New-Object System.Windows.Forms.NotifyIcon; $n.Icon = [System.Drawing.SystemIcons]::Information; $n.Visible = $true; $n.ShowBalloonTip(5000, "Claude Code", "Claude Code needs your attention", "Info")' 2>/dev/null
  exit 0
fi

# No notification method available. Silent exit
exit 0
