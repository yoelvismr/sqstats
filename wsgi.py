import os
import sys

# Add the project directory to the Python path
project_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, project_dir)

from app import create_app

# Create the Flask application
app, scheduler = create_app()

# Setup scheduler tasks for production
def setup_production_scheduler():
    """Setup scheduler tasks specifically for production environment"""
    from parsers.log import process_logs
    from services.metrics_service import MetricsService
    from services.notifications import (
        has_remote_commits_with_messages,
        set_commit_notifications,
    )
    import os
    from config import logger
    
    @scheduler.task(
        "interval", id="check_notifications", minutes=30, misfire_grace_time=1800
    )
    def check_notifications_task():
        repo_path = os.path.dirname(os.path.abspath(__file__))
        has_updates, messages = has_remote_commits_with_messages(repo_path)
        set_commit_notifications(has_updates, messages)

    @scheduler.task("interval", id="do_job_1", seconds=30, misfire_grace_time=900)
    def init_scheduler():
        log_file = os.getenv("SQUID_LOG", "/var/log/squid/access.log")
        logger.info(f"Production scheduler for file log: {log_file}")

        if not os.path.exists(log_file):
            logger.error(f"Log file not found: {log_file}")
            return
        else:
            process_logs(log_file)

    @scheduler.task("interval", id="cleanup_metrics", hours=1, misfire_grace_time=3600)
    def cleanup_old_metrics():
        try:
            success = MetricsService.cleanup_old_metrics()
            if success:
                logger.info("Cleanup of old metrics completed successfully")
            else:
                logger.warning("Error during cleanup of old metrics")
        except Exception as e:
            logger.error(f"Error in metrics cleanup task: {e}")

# Setup scheduler tasks for production
setup_production_scheduler()

if __name__ == "__main__":
    # This allows running the app directly with: python wsgi.py
    from flask_socketio import SocketIO
    from routes.stats_routes import realtime_data_thread
    
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
    socketio.start_background_task(realtime_data_thread, socketio)
    
    debug_mode = app.config.get('DEBUG', False)
    host = os.getenv("LISTEN_HOST", "0.0.0.0")
    port = int(os.getenv("LISTEN_PORT", "5000"))
    
    socketio.run(app, debug=debug_mode, host=host, port=port, allow_unsafe_werkzeug=True)