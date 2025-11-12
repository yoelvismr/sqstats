import os

# Configuración simplificada de Gunicorn para producción

# Server socket
bind = "127.0.0.1:5000"

# Worker processes
workers = 1
worker_class = "sync"
worker_connections = 1000

# Timeouts
timeout = 120
keepalive = 2

# Maximum requests per worker
max_requests = 1000
max_requests_jitter = 100

# Logging
accesslog = "/var/log/squidstats/gunicorn_access.log"
errorlog = "/var/log/squidstats/gunicorn_error.log"
loglevel = "info"

# Process naming
proc_name = "squidstats"

# Environment variables
raw_env = [
    "PYTHONPATH=/opt/SquidStats",
    "FLASK_DEBUG=False",
    "IN_GUNICORN=true"
]

# Preload app for better performance
preload_app = True

# Working directory
chdir = "/opt/SquidStats"