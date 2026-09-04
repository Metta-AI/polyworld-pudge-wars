from __future__ import annotations

import atexit
import logging
import os
import sys
from logging.handlers import QueueHandler, QueueListener
from queue import SimpleQueue
from urllib.request import Request, urlopen


class HttpLogHandler(logging.Handler):
    def __init__(self, url: str) -> None:
        super().__init__()
        self.url = url

    def emit(self, record: logging.LogRecord) -> None:
        message = self.format(record)
        print(message, flush=True)
        try:
            request = Request(self.url, data=message.encode(), method="POST")
            request.add_header("Content-Type", "text/plain")
            request.add_header("User-Agent", "coworld-pudgewars/0.1")
            with urlopen(request, timeout=10):
                pass
        except Exception:
            self.handleError(record)


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    url = os.environ.get("COGAME_LOG_URI")
    if url:
        queue: SimpleQueue[logging.LogRecord] = SimpleQueue()
        listener = QueueListener(queue, HttpLogHandler(url))
        listener.start()
        atexit.register(listener.stop)
        logger.addHandler(QueueHandler(queue))
    else:
        logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.propagate = False
    return logger
