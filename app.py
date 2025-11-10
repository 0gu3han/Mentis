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
    app = create_app()
    with app.app_context():
        db.create_all()
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=True)