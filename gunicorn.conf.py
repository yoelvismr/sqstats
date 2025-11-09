import os

# Server socket
bind = "127.0.0.1:5000"
backlog = 2048

# Worker processes (reducido para desarrollo/pruebas)
workers = 1
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 120
keepalive = 2

# Logging - usar rutas absolutas
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
    "PYTHONPATH=/opt/SquidStats",
    "FLASK_DEBUG=False",
    "IN_GUNICORN=true"
]

# Preload app for better performance
preload_app = True

# Worker tmp dir
worker_tmp_dir = "/dev/shm"

# Graceful timeout for worker shutdown
graceful_timeout = 30

# Change to the correct working directory
chdir = "/opt/SquidStats"