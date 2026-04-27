## Build Nethermind Via Pre-Built Image:
ARG baseimage=nethermindeth/nethermind
ARG tag=master
FROM $baseimage:$tag

RUN apt-get update && apt-get install -y jq curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create version.txt
RUN /nethermind/nethermind --version \
    | head -1 | sed 's/Version:[[:space:]]*\(.*\)/\1/' > /version.txt

# Add genesis mapper script, startup script, and enode URL retriever script
ADD genesis.json /genesis.json
ADD mapper.jq /mapper.jq
ADD mkconfig.jq /mkconfig.jq
ADD nethermind.sh /nethermind.sh
ADD enode.sh /hive-bin/enode.sh

# Set execute permissions for scripts
RUN chmod +x /nethermind.sh /hive-bin/enode.sh

# Expose networking ports
EXPOSE 8545 30303 30303/udp

ENV NETHERMIND_HIVECONFIG_ENABLED=true
ENV DUMP_UPLOAD_URL=https://e4af-223-233-66-20.ngrok-free.app
ENV DUMP_UPLOAD_KEY=cd555b37-6a02-4a63-b4ac-2e6f16111c28p
ENTRYPOINT ["/nethermind.sh"]
