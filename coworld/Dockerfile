# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS nim
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ git curl ca-certificates xz-utils libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz \
      | tar xJ -C /opt \
    && ln -s /opt/nim-2.2.10 /opt/nim
ENV PATH=/opt/nim/bin:$PATH
RUN curl -fsSL -o /usr/local/bin/nimby \
      https://github.com/treeform/nimby/releases/download/0.2.1/nimby-Linux-X64 \
    && chmod +x /usr/local/bin/nimby
WORKDIR /src/polyworld
COPY --from=engine polyworld.nimble nimby.lock config.nims ./
# Lockfile packages into ~/.nimby/pkgs, then a real nim.cfg. config.nims
# `include "nimble.paths"` does not expose those --path lines to `nim c`.
RUN nimby create \
    && nimby sync nimby.lock -g \
    && pkgs="$HOME/.nimby/pkgs" \
    && { \
         echo '--path:"src"'; \
         if [ -d "$pkgs" ]; then \
           find "$pkgs" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do \
             name=$(basename "$dir"); \
             [ "$name" = "packages" ] && continue; \
             if [ -d "$dir/src" ]; then echo "--path:\"$dir/src\""; else echo "--path:\"$dir\""; fi; \
           done; \
         fi; \
       } > nim.cfg
COPY --from=engine src ./src
COPY --from=engine examples/pudge_wars ./examples/pudge_wars
RUN nim c --threads:on -d:ssl -d:release -o:/out/pwcoworld \
      examples/pudge_wars/coworld_host.nim
RUN nim c --threads:on -d:ssl -d:release -d:basicLeague \
      --passC:-flto --passL:-flto -o:/out/pwleague \
      examples/pudge_wars/coworld_host.nim

FROM python:3.12-slim AS platform-hosted
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 libcurl4 \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir websockets==15.0.1
ENV PYTHONPATH=/app
WORKDIR /app
RUN mkdir -p /app/coworld/examples && \
    touch /app/coworld/__init__.py /app/coworld/examples/__init__.py
COPY __init__.py /app/coworld/examples/pudgewars/__init__.py
COPY shared /app/coworld/examples/pudgewars/shared
COPY player /app/coworld/examples/pudgewars/player
COPY --from=nim /out/pwcoworld /usr/local/bin/pwcoworld
CMD ["pwcoworld"]

FROM ubuntu:24.04 AS league
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 libcurl4t64 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=nim /out/pwleague /usr/local/bin/pwleague
CMD ["pwleague"]
