#!/usr/bin/env bash
# claude-launcher.sh — Run Claude Code sandboxed via bubblewrap (WSL/Ubuntu x64)
set -euo pipefail

ALLOWED_PATHS=("$HOME/source/")

SANDBOX="$HOME/.claude-sandbox"
CLAUDE_BIN="$SANDBOX/claude"
GCS="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Detect if we're inside bwrap by checking if PID 1 is bwrap
if [[ "$(cat /proc/1/comm 2>/dev/null)" != "bwrap" ]] && [[ "$$" != "2" ]]; then
  # Determine project directory
  PROJECT="$(realpath .)"

  # Check if project is in allowed locations
  allowed=false
  for prefix in "${ALLOWED_PATHS[@]}"; do
    if [[ "${PROJECT,,}" == "${prefix,,}"* ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" == false ]]; then
    echo "ERROR: '$PROJECT' is not in an allowed location."
    echo "Edit ALLOWED_PATHS to add more locations."
    exit 1
  fi

  # Ask for confirmation
  echo "Project directory: $PROJECT"
  echo -n "Allow Claude to access this directory? [y/N] "
  read -n 1 -r response && echo
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi

  echo "Preparing sandbox..."
  mkdir -p "$SANDBOX/home"

  # Initialize managed settings
  MANAGED_SETTINGS="$SANDBOX/managed-settings.json"
  if [[ ! -e "$MANAGED_SETTINGS" ]]; then
    echo '{"companyAnnouncements":["Running inside bubblewrap (bwrap) sandbox."]}' > "$MANAGED_SETTINGS"
  fi

  # Build bind mounts
  BINDS=()
  for p in /usr /lib /lib64 /bin /sbin /etc/resolv.conf /etc/ssl /etc/ca-certificates \
       /etc/alternatives /etc/ld.so.cache /etc/localtime /etc/passwd /etc/group \
       /etc/hosts /etc/nsswitch.conf /etc/host.conf; do
    [[ -e "$p" ]] && BINDS+=(--ro-bind "$p" "$p")
  done

  # Re-launch this script inside bwrap
  exec bwrap \
    --unshare-all \
    --share-net \
    --clearenv \
    --new-session \
    --die-with-parent \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --tmpfs /run \
    "${BINDS[@]}" \
    --bind "$SANDBOX/home" "$HOME" \
    --bind "$SANDBOX" "$SANDBOX" \
    --bind "$PROJECT" "$PROJECT" \
    --ro-bind "$MANAGED_SETTINGS" /etc/claude-code/managed-settings.json \
    --setenv HOME "$HOME" \
    --setenv TERM "${TERM:-xterm-256color}" \
    --setenv CLAUDE_CODE_DISABLE_AUTOUPDATE 1 \
    --setenv CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1 \
    --chdir "$PROJECT" \
    --ro-bind "$0" "$0" \
    -- bash "$0" "$@"
fi

# ====== Everything below runs inside bwrap ======

echo "Inside sandbox. Checking for updates..."

remote_ver="$(curl -fsSL "$GCS/latest")"
echo "Latest: $remote_ver"

needs_update=false
if [[ -x "$CLAUDE_BIN" ]]; then
  local_ver="$("$CLAUDE_BIN" --version 2>/dev/null || echo "")"
  if [[ "$local_ver" != *"$remote_ver"* ]]; then
    echo "Updating $local_ver to $remote_ver ..."
    needs_update=true
  else
    echo "Up to date."
  fi
else
  echo "Downloading $remote_ver ..."
  needs_update=true
fi

if [[ "$needs_update" == "true" ]]; then
  curl -fsSL -o "$CLAUDE_BIN" "$GCS/$remote_ver/linux-x64/claude"
  chmod +x "$CLAUDE_BIN"
fi

# Launch claude with arguments
exec "$CLAUDE_BIN" "$@"
