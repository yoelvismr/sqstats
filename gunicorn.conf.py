import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5000"
backlog = 2048

# Worker processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "gevent"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 120
keepalive = 2

# Logging
accesslog = "/var/log/squidstats/gunicorn_access.log"
errorlog = "/var/log/squidstats/gunicorn_error.log"
loglevel = "info"
capture_output = True

# Process naming
proc_name = "squidstats"

# Server mechanics
daemon = False
pidfile = "/var/run/squidstats/gunicorn.pid"
umask = 0

tmp_upload_dir = "/tmp"

# Environment variables
raw_env = [
    f"PYTHONPATH={os.getcwd()}",
    "FLASK_DEBUG=False"
]

# Preload app for better performance
preload_app = True

# Worker tmp dir
worker_tmp_dir = "/dev/shm"

# Graceful timeout for worker shutdown
graceful_timeout = 30