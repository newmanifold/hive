#!/bin/bash

# Startup script to initialize and boot a peer instance.
#
# This script assumes the following files:
#  - `nethermind` binary is located in the filesystem root
#  - `genesis.json` file is located in the filesystem root (mandatory)
#  - `chain.rlp` file is located in the filesystem root (optional)
#  - `blocks` folder is located in the filesystem root (optional)
#  - `keys` folder is located in the filesystem root (optional)
#
# This script assumes the following environment variables:
#
#  - HIVE_BOOTNODE             enode URL of the remote bootstrap node
#  - HIVE_NETWORK_ID           network ID number to use for the eth protocol
#  - HIVE_CHAIN_ID             network ID number to use for the eth protocol
#  - HIVE_NODETYPE             sync and pruning selector (archive, full, light)
#
# Forks:
#
#  - HIVE_FORK_HOMESTEAD       block number of the DAO hard-fork transition
#  - HIVE_FORK_DAO_BLOCK       block number of the DAO hard-fork transitionnsition
#  - HIVE_FORK_TANGERINE       block number of TangerineWhistle
#  - HIVE_FORK_SPURIOUS        block number of SpuriousDragon
#  - HIVE_FORK_BYZANTIUM       block number for Byzantium transition
#  - HIVE_FORK_CONSTANTINOPLE  block number for Constantinople transition
#  - HIVE_FORK_PETERSBURG      block number for ConstantinopleFix/PetersBurg transition
#  - HIVE_FORK_BERLIN          block number for Berlin transition
#  - HIVE_FORK_LONDON          block number for London
#
# Clique PoA:
#
#  - HIVE_CLIQUE_PERIOD        enables clique support. value is block time in seconds.
#  - HIVE_CLIQUE_PRIVATEKEY    private key for clique mining
#
# Other:
#
#  - HIVE_MINER                enables mining. value is coinbase address.
#  - HIVE_MINER_EXTRA          extra-data field to set for newly minted blocks
#  - HIVE_LOGLEVEL             Client log level
#
# These variables are not supported by Nethermind:
#
#  - HIVE_FORK_DAO_VOTE        whether the node support (or opposes) the DAO fork
#  - HIVE_GRAPHQL_ENABLED      if set, GraphQL is enabled on port 8545

# Immediately abort the script on any error encountered
set -e

# Generate JWT file if necessary
if [ "$HIVE_TERMINAL_TOTAL_DIFFICULTY" != "" ]; then
    JWT_SECRET="0x7365637265747365637265747365637265747365637265747365637265747365"
    echo -n $JWT_SECRET > /jwt.secret
fi

# Generate the genesis and chainspec file.
mkdir -p /chainspec
jq -f /mapper.jq /genesis.json > /chainspec/test.json

# Dump genesis. 
if [ "$HIVE_LOGLEVEL" -lt 4 ]; then
    echo "Supplied genesis state (trimmed, use --sim.loglevel 4 or 5 for full output):"
    jq 'del(.accounts[] | select(.balance == "0x123450000000000000000" or has("builtin")))' /chainspec/test.json
else
    echo "Supplied genesis state:"
    cat /chainspec/test.json
fi

# Check sync mode.
case "$HIVE_NODETYPE" in
    "" | full | archive | snap) ;;
    *)
        echo "Unsupported HIVE_NODETYPE = $HIVE_NODETYPE"
        exit 1 ;;
esac

# Generate the config file.
mkdir /configs
jq -n -f /mkconfig.jq > /configs/test.json

echo "test.json"
cat /configs/test.json

# Set bootnode.
if [ -n "$HIVE_BOOTNODE" ]; then
    echo "[\"$HIVE_BOOTNODE\"]" > /nethermind/static-nodes.json
fi

# Configure logging.
export NO_COLOR=1
LOG_FLAG=""
if [ "$HIVE_LOGLEVEL" != "" ]; then
    case "$HIVE_LOGLEVEL" in
        0)   LOG=OFF ;;
        1)   LOG=ERROR ;;
        2)   LOG=WARN  ;;
        3)   LOG=INFO  ;;
        4)   LOG=DEBUG ;;
        5)   LOG=TRACE ;;
    esac
    LOG_FLAG="--log $LOG"
fi

echo "Running Nethermind..."
export DOTNET_DbgEnableMiniDump=1
export DOTNET_DbgMiniDumpType=1
export DOTNET_DbgMiniDumpName=/tmp/coredump.%e.%p.%t
export DOTNET_CreateDumpDiagnostics=1
export DOTNET_EnableCrashReport=1
/nethermind/nethermind --config /configs/test.json $LOG_FLAG &
NM_PID=$!
set +e
wait $NM_PID
EXIT_CODE=$?
set -e

# Ignore SIGTERM during dump upload so hive container cleanup doesn't kill us
trap '' TERM

for f in /tmp/coredump.*.crashreport.json; do
    [ -f "$f" ] || continue
    echo "=== CRASH REPORT: $f ==="
    cat "$f"
    echo "=== END CRASH REPORT ==="
done
if [ -n "$DUMP_UPLOAD_URL" ]; then
    for f in /tmp/coredump.*; do
        [ -f "$f" ] || continue
        SIZE=$(stat -c%s "$f" 2>/dev/null || echo 0)
        echo "Uploading $f ($SIZE bytes) to $DUMP_UPLOAD_URL..."
        curl -s -X POST "$DUMP_UPLOAD_URL" \
            -H "X-Api-Key: $DUMP_UPLOAD_KEY" \
            -H "X-Filename: $(basename $f)" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@$f" \
            --max-time 300 && echo "Upload OK" || echo "Upload failed for $f"
    done
fi
exit $EXIT_CODE
