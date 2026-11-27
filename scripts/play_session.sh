#!/bin/sh
# The runner part of .github/workflows/play-session.yml: the game server,
# and a quick tunnel of Cloudflare to it. The address goes into the summary
# of the job. At the end, the world file and the records of the bridges are
# in $RUNNER_TEMP/session.
#
# The method is the method of scripts/remote_ssh_runner.sh in sntran/BEAM.com.
#
# Environment: MINUTES (60, 120 at most), WORKERS (30), HELPERS (0),
# PROBE_TRIES (60), and for a test: CLOUDFLARED (a cloudflared that is there
# already) and BEAM_DIR (a directory that has `mix` already).
set -u
: "${MINUTES:=60}" "${WORKERS:=30}" "${HELPERS:=0}" "${PROBE_TRIES:=60}"
[ "$MINUTES" -gt 120 ] && MINUTES=120
[ "$MINUTES" -lt 1 ] && MINUTES=1
TMP=${RUNNER_TEMP:-/tmp}
OUT=$TMP/session
PORT=${PORT:-4000}
mkdir -p "$OUT"
log=$OUT/server.log
tunnel_log=$TMP/cloudflared.log
summary=${GITHUB_STEP_SUMMARY:-$OUT/summary.md}

# beam.com 0.1.0-rc.8: Erlang/OTP and Elixir in one file, with its SHA-256.
BEAM_VERSION=v0.1.0-rc.8
BEAM_SHA=6f0898976b4c51b0e7d4079bc421072c82e3c8c6d0334eb7becc17a1787dbc72
# cloudflared 2026.10.7, with the SHA-256 of each file.
CF_VERSION=2026.10.7

sha256() {
    (sha256sum < "$1" 2>/dev/null || shasum -a 256 < "$1") | cut -d' ' -f1
}

# Gets a file and makes sure that it is the file that this script knows.
fetch() {
    curl -fsSL -o "$2" "$1" || return 1
    got=$(sha256 "$2")
    if [ "$got" != "$3" ]; then
        echo "play session: the SHA-256 of $2 is $got, not $3" >&2
        return 1
    fi
}

beam() {
    BEAM_DIR=$TMP/beam
    mkdir -p "$BEAM_DIR"
    fetch "https://github.com/sntran/BEAM.com/releases/download/$BEAM_VERSION/beam.com" \
        "$BEAM_DIR/beam.com" "$BEAM_SHA" || return 1
    chmod +x "$BEAM_DIR/beam.com"
    ln -sf beam.com "$BEAM_DIR/mix"
    ln -sf beam.com "$BEAM_DIR/iex"
}

cloudflared() {
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) f=cloudflared-linux-amd64
            s=1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872 ;;
        Linux-aarch64|Linux-arm64) f=cloudflared-linux-arm64
            s=3df43aedc9ff291d1735b5cb576cb97e0b157488796db2e32b28aecabb445775 ;;
        *) echo "play session: no cloudflared for $(uname -s) $(uname -m)" >&2; return 1 ;;
    esac
    fetch "https://github.com/cloudflare/cloudflared/releases/download/$CF_VERSION/$f" \
        "$TMP/$f" "$s" || return 1
    chmod +x "$TMP/$f" && CLOUDFLARED=$TMP/$f
}

server_pid= tunnel_pid=
cleanup() {
    [ -n "$tunnel_pid" ] && kill "$tunnel_pid" 2>/dev/null
    if [ -n "$server_pid" ]; then
        # The server saves the world when it stops in the usual way.
        kill -TERM "$server_pid" 2>/dev/null
        n=0
        while kill -0 "$server_pid" 2>/dev/null && [ $n -lt 100 ]; do sleep 0.2; n=$((n + 1)); done
    fi
    if [ -f "$OUT/world.bin" ]; then
        COLONY_SAVE_FILE=$OUT/world.bin mix colony.records > "$OUT/records.json" 2>> "$log"
        echo "play session: the world file and the records are in $OUT"
        {
            echo
            echo "The session is at its end. The records of the bridges:"
            echo
            echo '```json'
            cat "$OUT/records.json"
            echo '```'
        } >> "$summary"
    fi
}
trap cleanup EXIT

# Wait at most $2 seconds for the pattern $1 in the file $3, while the
# process $4 runs.
wait_for() {
    n=0
    while [ $n -lt $(( $2 * 5 )) ]; do
        m=$(grep -E -o "$1" "$3" 2>/dev/null | head -n 1)
        if [ -n "$m" ]; then echo "$m"; return 0; fi
        kill -0 "$4" 2>/dev/null || return 1
        sleep 0.2
        n=$((n + 1))
    done
    return 1
}

[ -n "${BEAM_DIR:-}" ] || beam || exit 1
PATH=$BEAM_DIR:$PATH
export PATH MIX_ENV=prod

mix local.hex --force > "$log" 2>&1 || { cat "$log"; exit 1; }
mix deps.get --only prod >> "$log" 2>&1 || { cat "$log"; exit 1; }
mix compile >> "$log" 2>&1 || { cat "$log"; exit 1; }

PORT=$PORT COLONY_WORKERS=$WORKERS COLONY_HELPERS=$HELPERS COLONY_SAVE_FILE=$OUT/world.bin \
    mix phx.server >> "$log" 2>&1 &
server_pid=$!
if ! wait_for 'Running ColonyWeb.Endpoint' 300 "$log" "$server_pid" > /dev/null; then
    cat "$log"
    echo "play session: the server did not start" >&2
    exit 1
fi
tail -n 3 "$log"

[ -n "${CLOUDFLARED:-}" ] || cloudflared || exit 1
"$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" > "$tunnel_log" 2>&1 &
tunnel_pid=$!
if ! host=$(wait_for '[a-z0-9-]+\.trycloudflare\.com' 120 "$tunnel_log" "$tunnel_pid"); then
    cat "$tunnel_log"
    echo "play session: the tunnel did not start" >&2
    exit 1
fi
# The name of the tunnel needs some seconds in DNS.
n=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' "https://$host/")" = 200 ]; do
    n=$((n + 1))
    if [ $n -ge "$PROBE_TRIES" ]; then
        echo "play session: https://$host/ does not answer" >&2
        break
    fi
    sleep 2
done
# With no tunnel, no player can open the address: the job fails here.
if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    cat "$tunnel_log"
    echo "play session: the tunnel stopped" >&2
    exit 1
fi

{
    echo "## Colony play session"
    echo
    echo "Open this address on a phone or a computer:"
    echo
    echo "**https://$host/**"
    echo
    echo "- The session runs for $MINUTES minutes, with $WORKERS workers and $HELPERS helpers at the start."
    echo "- https://$host/?demo=1 shows the demo mode. https://$host/?stats=1 shows the numbers of the page."
    echo "- At the end, the artifact of this run has the world file and the records of the bridges."
} >> "$summary"
echo "play session: https://$host/ for $MINUTES minutes, $WORKERS workers, $HELPERS helpers"

# Wait for the end of the session, or for the end of the server or of the tunnel.
end=$(( $(date +%s) + MINUTES * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "play session: the server stopped" >&2
        exit 1
    fi
    if ! kill -0 "$tunnel_pid" 2>/dev/null; then
        tail -n 20 "$tunnel_log"
        echo "play session: the tunnel stopped" >&2
        exit 1
    fi
    sleep 5
done
echo "play session: the time is at its end"
