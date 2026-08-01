import os
from flask import Flask
from flask_migrate import Migrate
from flask_cors import CORS
from models import db
from routes import bp as routes_bp

def create_app():
    # Config
    UPLOAD_DIR = os.environ.get("UPLOAD_DIR", "uploads")
    DB_URL = os.environ.get("DATABASE_URL", "sqlite:///mentis.db")

    os.makedirs(UPLOAD_DIR, exist_ok=True)

    app = Flask(__name__)
    CORS(app)
    app.config["SQLALCHEMY_DATABASE_URI"] = DB_URL
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["UPLOAD_DIR"] = UPLOAD_DIR

    # Initialize extensions
    db.init_app(app)
    migrate = Migrate(app, db)

    # Register routes (blueprint)
    app.register_blueprint(routes_bp)

    return app

if __name__ == "__main__":
    import socket

    app = create_app()
    with app.app_context():
        db.create_all()

    port = int(os.environ.get("PORT", 5001))

    # Advertise on the local network via Bonjour so the iOS app can auto-discover
    _zc = None
    try:
        from zeroconf import ServiceInfo, Zeroconf
        _hostname = socket.gethostname()
        try:
            _ip = socket.gethostbyname(_hostname)
        except socket.gaierror:
            _ip = "127.0.0.1"
        _zc = Zeroconf()
        _info = ServiceInfo(
            "_mentis._tcp.local.",
            "Mentis._mentis._tcp.local.",
            addresses=[socket.inet_aton(_ip)],
            port=port,
            properties={b"version": b"1"},
            server=f"{_hostname}.local.",
        )
        _zc.register_service(_info)
        print(f"[Bonjour] Advertising Mentis at http://{_ip}:{port}")
    except ImportError:
        print("[Bonjour] zeroconf not installed — run: pip install zeroconf")
    except Exception as e:
        print(f"[Bonjour] Registration failed: {e}")

    try:
        app.run(host="0.0.0.0", port=port, debug=True, use_reloader=False)
    finally:
        if _zc:
            _zc.unregister_all_services()
            _zc.close()
    