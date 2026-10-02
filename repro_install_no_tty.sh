#!/usr/bin/env bash
# supermemory.ai/install (server 0.0.8): dies at the API-key prompt when /dev/tty is readable/writable by
# permission but there is no controlling terminal (CI, docker without -t, agent shells).
# Expected on affected box: "line N: /dev/tty: No such device or address", exit 1.
D=$(mktemp -d)
curl -fsSL https://supermemory.ai/install -o "$D/install.sh"
SUPERMEMORY_INSTALL_DIR=$D/i SUPERMEMORY_BIN_DIR=$D/b SUPERMEMORY_NO_START=1 \
  setsid bash "$D/install.sh" < /dev/null; echo "exit=$?"
echo "workaround: SUPERMEMORY_NO_PROMPT=1"
