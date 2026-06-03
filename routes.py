import os
import uuid
import shutil
import subprocess
from threading import Thread
from datetime import datetime
from flask import Blueprint, request, jsonify, send_from_directory, make_response, current_app
from models import db, User, Room, Anchor, Object, Review
from utils import allowed_file, schedule_next

bp = Blueprint("api", __name__)


def _blender_path():
    """Find Blender executable on macOS or PATH."""
    candidates = [
        shutil.which("blender"),
        "/Applications/Blender.app/Contents/MacOS/Blender",
        "/Applications/Blender.app/Contents/MacOS/blender",
        os.path.expanduser("~/Applications/Blender.app/Contents/MacOS/Blender"),
    ]
    return next((p for p in candidates if p and os.path.isfile(p)), None)


def _convert_usdz_to_glb(app, room_id: int, usdz_path: str):
    """Run Blender in background to convert USDZ → GLB, then update the DB."""
    blender = _blender_path()
    if not blender:
        return  # Blender not installed — keep USDZ as-is

    glb_path = usdz_path.rsplit(".", 1)[0] + ".glb"

    # iOS PhotogrammetrySession USDZ uses ARKit Y-up, but Blender's USD importer
    # does not apply the Y→Z axis correction automatically for all USDZ variants.
    # We rotate 180° on X (negates Y and Z) which corrects the upside-down result
    # that the default import→export pipeline produces.
    script = (
        "import bpy, math;"
        "bpy.ops.object.select_all(action='SELECT');"
        "bpy.ops.object.delete();"
        f"bpy.ops.wm.usd_import(filepath=r'{usdz_path}',scale=1.0,import_cameras=False,import_lights=False);"
        "bpy.ops.object.select_all(action='SELECT');"
        "bpy.ops.transform.rotate(value=math.pi,orient_axis='X',orient_type='GLOBAL');"
        "bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);"
        f"bpy.ops.export_scene.gltf(filepath=r'{glb_path}',export_format='GLB',"
        "export_apply=True,export_texcoords=True,export_normals=True,export_materials='EXPORT')"
    )
    try:
        result = subprocess.run(
            [blender, "--background", "--python-expr", script],
            timeout=600, capture_output=True
        )
        if result.returncode != 0 or not os.path.exists(glb_path):
            return
    except (subprocess.TimeoutExpired, OSError):
        return

    # Write a sidecar so the web viewer knows this GLB was converted from USDZ
    # and can apply the matching axis correction for display.
    try:
        with open(glb_path + ".axis_fixed", "w") as f:
            f.write("1")
    except OSError:
        pass

    with app.app_context():
        room = Room.query.get(room_id)
        if room:
            room.glb_path = glb_path
            db.session.commit()
    try:
        os.remove(usdz_path)
    except OSError:
        pass


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

        if ext == "usdz" and _blender_path():
            app = current_app._get_current_object()
            Thread(target=_convert_usdz_to_glb, args=(app, room.id, path), daemon=True).start()

        return {"room_id": room.id, "name": room.name, "converting": ext == "usdz"}

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
        ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        mime = {
            "glb":  "model/gltf-binary",
            "gltf": "model/gltf+json",
            "usdz": "model/vnd.usdz+zip",
            "obj":  "model/obj",
        }.get(ext, "application/octet-stream")
        response = make_response(
            send_from_directory(directory, filename, as_attachment=False, mimetype=mime)
        )
        sidecar = os.path.join(directory, filename + ".axis_fixed")
        if os.path.exists(sidecar):
            response.headers["X-Axis-Fixed"] = "true"
        return response

@bp.route("/rooms/<int:room_id>", methods=["DELETE"])
def delete_room(room_id: int):
        room = Room.query.get_or_404(room_id)
        if room.glb_path and os.path.exists(room.glb_path):
            try:
                os.remove(room.glb_path)
            except OSError:
                pass
        db.session.delete(room)
        db.session.commit()
        return {"ok": True}

@bp.route("/anchors", methods=["POST"])
def create_anchor():
        data = request.json or {}
        required = ["room_id", "pos", "normal"]
        if any(k not in data for k in required):
            return {"error": "room_id, pos[x,y,z], normal[x,y,z] required"}, 400

        raw_id = data["room_id"]
        try:
            room_id = int(raw_id)
        except (ValueError, TypeError):
            # External room (e.g. Sketchfab) — find or auto-create a placeholder Room row
            placeholder = f"external:{raw_id}"
            room = Room.query.filter_by(glb_path=placeholder).first()
            if not room:
                user = User.query.first()
                if not user:
                    user = User(email="system@mentis.app")
                    db.session.add(user)
                    db.session.flush()
                room = Room(user_id=user.id, name=str(raw_id), glb_path=placeholder)
                db.session.add(room)
                db.session.flush()
            room_id = room.id

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
        raw = request.args.get("room_id")
        room_id = None
        if raw is not None:
            try:
                room_id = int(raw)
            except ValueError:
                placeholder = f"external:{raw}"
                room = Room.query.filter_by(glb_path=placeholder).first()
                room_id = room.id if room else -1
        q = Anchor.query
        if room_id is not None:
            q = q.filter_by(room_id=room_id)
        anchors = [
            {
                "id": a.id,
                "room_id": a.room_id,
                "label": a.label,
                "pos": [a.pos_x, a.pos_y, a.pos_z],
                "normal": [a.n_x, a.n_y, a.n_z],
                "objects": [
                    {
                        "id": obj.id,
                        "title": obj.title,
                        "kind": obj.kind,
                        "body": obj.body,
                        "media_url": obj.media_url,
                    }
                    for obj in a.objects
                ]
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