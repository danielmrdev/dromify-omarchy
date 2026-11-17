#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYER="$ROOT/bin/dromify-player"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/state"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/mpv"
cat > "$TMP/bin/socat" <<'EOF'
#!/usr/bin/env bash
request="$(cat)"
if [[ "$request" == *'"get_version"'* ]]; then
  printf '%s\n' '{"data":{"version":"fixture"}}'
elif [[ "$request" == *'"audio-device-list"'* ]]; then
  printf '%s\n' \
    '{"data":[{"name":"auto","description":"Autoselect device"},{"name":"alsa/default","description":"Raw ALSA"},{"name":"pipewire/office","description":"Office speakers"},{"name":"pipewire/homepod_bridge","description":"HomePods <unsafe>"}]}' \
    '{"data":"auto"}'
elif [[ "$request" == *'"set_property","audio-device"'* ]]; then
  printf '%s\n' "$request" >> "$MOCK_REQUESTS"
  printf '%s\n' '{"error":"success"}'
else
  echo "unexpected IPC request" >&2
  exit 1
fi
EOF
cat > "$TMP/bin/pactl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_PACTL"
EOF
chmod +x "$TMP/bin/"*
export XDG_RUNTIME_DIR="$TMP/runtime"
export XDG_STATE_HOME="$TMP/state"
export PATH="$TMP/bin:$PATH"
export MOCK_REQUESTS="$TMP/requests"
export MOCK_PACTL="$TMP/pactl"

python3 - "$XDG_RUNTIME_DIR/dromify-mpv.sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.close()
PY

outputs="$("$PLAYER" audio-devices)"
jq -e '.current == "auto" and ([.devices[].name] == ["auto","pipewire/office","pipewire/homepod_bridge"])' <<<"$outputs" >/dev/null

"$PLAYER" audio-device 'pipewire/homepod_bridge' >/dev/null
jq -e '.command == ["set_property","audio-device","pipewire/homepod_bridge"]' "$MOCK_REQUESTS" >/dev/null

if "$PLAYER" audio-device 'pipewire/office"; ["run","evil"]' >/dev/null 2>&1; then
  echo "accepted an invalid audio output id" >&2
  exit 1
fi
[[ ! -e "$MOCK_PACTL" ]]
printf 'audio-output: ok\n'
