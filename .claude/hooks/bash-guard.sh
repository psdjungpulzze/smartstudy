#!/usr/bin/env bash
# bash-guard.sh
#
# Claude Code PreToolUse hook (matcher: Bash).
# Denies destructive command patterns that glob-style permission matchers
# can't reliably catch: rm -rf on home/system paths, pipe-to-shell from
# network, force-push to protected branches, raw disk writes.
#
# Contract: always exits 0. The "deny" signal is the JSON payload on stdout,
# which sets hookSpecificOutput.permissionDecision=deny.

set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
[ -z "$CMD" ] && exit 0

deny() {
  jq -cn --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# ---------------------------------------------------------------------------
# rm -rf on home directory (top-level only; narrow subpaths like ~/.cache/foo
# are allowed so normal dev workflows work)
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\brm[[:space:]]+-[rRf]{1,3}[[:space:]]+(~|\$HOME|/home/[^/[:space:]]+)(/\*|/\.\*)?([[:space:]]|$|;|&)'; then
  deny "Blocked: rm -rf on home directory. If you really need this, run it outside Claude."
fi

# ---------------------------------------------------------------------------
# rm -rf on system paths
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\brm[[:space:]]+-[rRf]{1,3}[[:space:]]+(/|/usr|/etc|/var|/lib|/bin|/sbin|/boot|/opt)([[:space:]]|$|;|&)'; then
  deny "Blocked: rm -rf on system path. Never needed for dev work."
fi

# ---------------------------------------------------------------------------
# Pipe network content to a shell (the #1 prompt-injection RCE vector)
# Blocks: curl/wget ... | sh | bash | zsh | fish | dash
# Allows: curl ... | jq, curl ... | tee, etc.
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\b(curl|wget|fetch)\b[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|fish|dash|ksh)([[:space:]]|$|;|&)'; then
  deny "Blocked: piping network content to a shell. This is the top prompt-injection → RCE vector. Download first, inspect, then run."
fi

# ---------------------------------------------------------------------------
# Force-push to protected branches
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+push\b'; then
  if printf '%s' "$CMD" | grep -qE '(\s-f\b|--force\b|--force-with-lease\b)'; then
    if printf '%s' "$CMD" | grep -qE '\b(main|master|production|release|prod)\b'; then
      deny "Blocked: force-push to a protected branch (main/master/production/release/prod). Open a PR instead."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Raw disk writes
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\b(mkfs[\.a-z0-9]*|dd[[:space:]]+if=[^[:space:]]+[[:space:]]+of=/dev/)'; then
  deny "Blocked: direct disk write (mkfs/dd to /dev). This destroys data."
fi

# ---------------------------------------------------------------------------
# Recursive chmod/chown on broad paths (home, root filesystem)
# ---------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE '\b(chmod|chown)[[:space:]]+(-R|--recursive)\b[^|;&]*[[:space:]](~|\$HOME|/|/home|/usr|/etc)([[:space:]]|$|;|&|/)'; then
  deny "Blocked: recursive chmod/chown on broad path. Narrow the scope."
fi

exit 0
