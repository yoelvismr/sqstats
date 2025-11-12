import os
import sys

# Add the project directory to the Python path
project_dir = "/opt/SquidStats"
sys.path.insert(0, project_dir)

# Set environment variable for production
os.environ['IN_GUNICORN'] = 'true'

from app import create_app

# Create the Flask application
app, scheduler = create_app()


if __name__ == "__main__":
    from flask_socketio import SocketIO
    from routes.stats_routes import realtime_data_thread
    
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
    socketio.start_background_task(realtime_data_thread, socketio)
    
    debug_mode = app.config.get('DEBUG', False)
    host = os.getenv("LISTEN_HOST", "0.0.0.0")
    port = int(os.getenv("LISTEN_PORT", "5000"))
    
    socketio.run(app, debug=debug_mode, host=host, port=port, allow_unsafe_werkzeug=True)