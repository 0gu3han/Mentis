from datetime import datetime, timedelta, timezone
from typing import Set

# File extensions allowed for upload
ALLOWED_EXTS: Set[str] = {"glb", "gltf", "usdz", "obj"}

def allowed_file(filename: str) -> bool:
    """Check if the file extension is allowed."""
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTS

def schedule_next(review, grade: int):
    """SM-2 lite scheduling algorithm."""
    grade = max(0, min(5, int(grade)))
    if grade < 3:
        review.reps = 0
        review.interval_d = 1
    else:
        if review.reps == 0:
            review.interval_d = 1
        elif review.reps == 1:
            review.interval_d = 6
        else:
            review.interval_d = int(round(review.interval_d * review.easiness))
        review.reps += 1
        review.easiness = max(1.3, review.easiness + (0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)))
    review.last_grade = grade
    review.next_due = datetime.now(timezone.utc) + timedelta(days=review.interval_d)