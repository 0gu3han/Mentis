import os
import uuid
from datetime import datetime
from flask import Blueprint, request, jsonify, send_from_directory, current_app
from models import db, User, Room, Anchor, Object, Review
from utils import allowed_file, schedule_next

bp = Blueprint("api", __name__)


@bp.route("/health")
def health():
    return {"ok": True}

@bp.route("/auth/login", methods=["POST"])
def login():
        email = request.json.get("email")
        if not email:
            return {"error": "email required"}, 400
        user = User.query.filter_by(email=email).first()
        if not user:
            user = User(email=email)
            db.session.add(user)
            db.session.commit()
        return {"user_id": user.id, "email": user.email}

@bp.route("/rooms", methods=["POST"])
def create_room():
        user_id = request.form.get("user_id")
        name = request.form.get("name", "My Room")
        f = request.files.get("file")
        if not (user_id and f and allowed_file(f.filename)):
            return {"error": "user_id, file (glb/gltf/obj/usdz) required"}, 400

        ext = f.filename.rsplit(".", 1)[1].lower()
        fname = f"{uuid.uuid4().hex}.{ext}"
        path = os.path.join(current_app.config["UPLOAD_DIR"], fname)
        f.save(path)

        room = Room(user_id=int(user_id), name=name, glb_path=path)
        db.session.add(room)
        db.session.commit()
        return {"room_id": room.id, "name": room.name}

@bp.route("/rooms", methods=["GET"])
def list_rooms():
        user_id = request.args.get("user_id", type=int)
        q = Room.query
        if user_id:
            q = q.filter_by(user_id=user_id)
        rooms = [
            {
                "id": r.id,
                "name": r.name,
                "created_at": r.created_at.isoformat(),
            }
            for r in q.order_by(Room.created_at.desc()).all()
        ]
        return {"rooms": rooms}

@bp.route("/rooms/<int:room_id>/glb")
def serve_glb(room_id: int):
        room = Room.query.get_or_404(room_id)
        directory, filename = os.path.split(room.glb_path)
        return send_from_directory(directory, filename, as_attachment=False)

@bp.route("/anchors", methods=["POST"])
def create_anchor():
        data = request.json or {}
        required = ["room_id", "pos", "normal"]
        if any(k not in data for k in required):
            return {"error": "room_id, pos[x,y,z], normal[x,y,z] required"}, 400
        room_id = int(data["room_id"])
        label = data.get("label", "")
        pos = data["pos"]
        nrm = data["normal"]

        a = Anchor(
            room_id=room_id,
            label=label,
            pos_x=float(pos[0]), pos_y=float(pos[1]), pos_z=float(pos[2]),
            n_x=float(nrm[0]), n_y=float(nrm[1]), n_z=float(nrm[2]),
        )
        db.session.add(a)
        db.session.commit()
        return {"anchor_id": a.id}

@bp.route("/anchors", methods=["GET"])
def list_anchors():
        room_id = request.args.get("room_id", type=int)
        q = Anchor.query
        if room_id:
            q = q.filter_by(room_id=room_id)
        anchors = [
            {
                "id": a.id,
                "room_id": a.room_id,
                "label": a.label,
                "pos": [a.pos_x, a.pos_y, a.pos_z],
                "normal": [a.n_x, a.n_y, a.n_z],
            }
            for a in q.order_by(Anchor.created_at.asc()).all()
        ]
        return {"anchors": anchors}

@bp.route("/anchors/<int:anchor_id>", methods=["DELETE"])
def delete_anchor(anchor_id: int):
        a = Anchor.query.get_or_404(anchor_id)
        db.session.delete(a)
        db.session.commit()
        return {"ok": True}

@bp.route("/objects", methods=["POST"])
def create_object():
        data = request.json or {}
        required = ["anchor_id", "title"]
        if any(k not in data for k in required):
            return {"error": "anchor_id, title required"}, 400
        obj = Object(
            anchor_id=int(data["anchor_id"]),
            title=data["title"],
            kind=data.get("kind", "text"),
            body=data.get("body", ""),
            media_url=data.get("media_url", ""),
        )
        db.session.add(obj)
        db.session.flush()
        rv = Review(object_id=obj.id)
        db.session.add(rv)
        db.session.commit()
        return {"object_id": obj.id}

@bp.route("/review/next")
def review_next():
        room_id = request.args.get("room_id", type=int)
        q = db.session.query(Review).join(Object).join(Anchor)
        if room_id:
            q = q.filter(Anchor.room_id == room_id)
        q = q.filter(Review.next_due <= datetime.utcnow()).order_by(Review.next_due.asc())
        item = q.first()
        if not item:
            return {"due": None}
        obj = item.obj
        a = obj.anchor
        return {
            "review_id": item.id,
            "object": {
                "id": obj.id, "title": obj.title, "kind": obj.kind,
                "body": obj.body, "media_url": obj.media_url
            },
            "anchor": {
                "id": a.id, "pos": [a.pos_x, a.pos_y, a.pos_z], "normal": [a.n_x, a.n_y, a.n_z]
            },
        }

@bp.route("/review/<int:review_id>", methods=["POST"])
def review_submit(review_id: int):
        data = request.json or {}
        grade = int(data.get("grade", 3))
        rv = Review.query.get_or_404(review_id)
        schedule_next(rv, grade)
        db.session.commit()
        return {"ok": True, "next_due": rv.next_due.isoformat()}