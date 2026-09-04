# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS nim
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ git curl ca-certificates xz-utils libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz \
      | tar xJ -C /opt \
    && ln -s /opt/nim-2.2.10 /opt/nim
ENV PATH=/opt/nim/bin:$PATH
WORKDIR /src/polyworld
COPY --from=engine . /src/polyworld
# Install every polyworld.nimble require. A hand-maintained subset omitted
# fluffy, which coworld_host pulls in through polyworld/profiles.
# nimble setup writes nimble.paths, but the committed config.nims does not
# include it, so the compiler would otherwise miss ~/.nimble/pkgs2.
RUN nimble install --depsOnly -y \
    && nimble setup \
    && printf '\ninclude "nimble.paths"\n' >> config.nims
RUN nim c --threads:on -d:ssl -d:release -o:/out/pwcoworld \
      examples/pudge_wars/coworld_host.nim

FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 \
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
