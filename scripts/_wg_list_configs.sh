#!/bin/sh
for f in /etc/wireguard/*.conf; do
    [ -f "$f" ] || continue
    iface=$(basename "$f" .conf)
    [ "$iface" = "wg-vps" ] && continue # system-managed (wg-quick@wg-vps)
    label=$(grep "^#Label:" "$f" 2>/dev/null | head -1 | sed 's/^#Label:[[:space:]]*//')
    if [ -n "$label" ]; then
        echo "$iface|$label"
    else
        echo "$iface|"
    fi
done
