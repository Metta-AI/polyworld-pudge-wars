FROM python:3.12-slim
RUN pip install --no-cache-dir websockets==15.0.1
WORKDIR /app
COPY player /app/coworld/examples/pudgewars/player
COPY shared /app/coworld/examples/pudgewars/shared
ENV PYTHONPATH=/app
ENV PUDGE_PERSONALITY=rusher
ARG POLICY_ARM=combined
ENV PUDGE_POLICY_ARM=$POLICY_ARM
CMD ["python", "-m", "coworld.examples.pudgewars.player.player"]
