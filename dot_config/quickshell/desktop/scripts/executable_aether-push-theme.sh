#!/bin/bash
set -euo pipefail

# Theme owns the validated dedicated-palette resolver, including the legacy
# fallback. Never push global Aether colors over Quickshell-specific overrides.
qs -c desktop ipc call theme reload >/dev/null 2>&1 || true
qs -c desktop ipc call background refresh >/dev/null 2>&1 || true
