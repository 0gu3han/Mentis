from datetime import datetime
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class User(db.Model):
    __tablename__ = "users"
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class Room(db.Model):
    __tablename__ = "rooms"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name = db.Column(db.String(255), nullable=False)
    glb_path = db.Column(db.String(512), nullable=False)
    tri_count = db.Column(db.Integer, default=0)
    scale_m_per_unit = db.Column(db.Float, default=1.0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    user = db.relationship("User", backref=db.backref("rooms", lazy=True))

class Anchor(db.Model):
    __tablename__ = "anchors"
    id = db.Column(db.Integer, primary_key=True)
    room_id = db.Column(db.Integer, db.ForeignKey("rooms.id"), nullable=False)
    label = db.Column(db.String(255), default="")
    pos_x = db.Column(db.Float, nullable=False)
    pos_y = db.Column(db.Float, nullable=False)
    pos_z = db.Column(db.Float, nullable=False)
    n_x = db.Column(db.Float, nullable=False)
    n_y = db.Column(db.Float, nullable=False)
    n_z = db.Column(db.Float, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    room = db.relationship("Room", backref=db.backref("anchors", lazy=True, cascade="all, delete-orphan"))

class Object(db.Model):
    __tablename__ = "objects"
    id = db.Column(db.Integer, primary_key=True)
    anchor_id = db.Column(db.Integer, db.ForeignKey("anchors.id"), nullable=False)
    title = db.Column(db.String(255), nullable=False)
    kind = db.Column(db.String(32), default="text")  # text/image/audio/quiz
    body = db.Column(db.Text, default="")
    media_url = db.Column(db.String(512), default="")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    anchor = db.relationship("Anchor", backref=db.backref("objects", lazy=True, cascade="all, delete-orphan"))

class Review(db.Model):
    __tablename__ = "reviews"
    id = db.Column(db.Integer, primary_key=True)
    object_id = db.Column(db.Integer, db.ForeignKey("objects.id"), nullable=False)
    next_due = db.Column(db.DateTime, default=datetime.utcnow)
    easiness = db.Column(db.Float, default=2.5)
    interval_d = db.Column(db.Integer, default=1)
    reps = db.Column(db.Integer, default=0)
    last_grade = db.Column(db.Integer, default=0)
    obj = db.relationship("Object", backref=db.backref("review", uselist=False, cascade="all, delete-orphan"))