"""Multi-view crops of scanned objects from the saved 640x480 keyframes (ScanFrameRecorder).

Conventions (ColorSampler.swift / ScanFrameRecorder.swift):
- cameras.json[i] = ScanCamera {transform: camera->world, 4 columns; fx fy cx cy in px of the
  stored JPEG (already scaled to 640x480); width, height}. Image kept in landscape sensor orientation.
- camera space: x right (along long side), y up, looking down -z.  u = fx*x/(-z)+cx, v = fy*(-y)/(-z)+cy.
- geometry.json objects: transform (column-major 4x4, box center), dimensions (w,h,d) along local x,y,z.
- upright (portrait) image = sensor image rotated 90 deg clockwise (AutoPhoto.swift CameraPose.upright).
"""
import json, os
import numpy as np
from PIL import Image

BENCH = "/tmp/claude-501/bench"
FRAMES = f"{BENCH}/ipad_frames"


def mat(t):
    return np.array(t["columns"], dtype=np.float64).T  # columns -> 4x4 (column-major storage)


def corners(obj):
    T = mat(obj["transform"]); d = np.array(obj["dimensions"], np.float64)
    pts = np.array([[x, y, z, 1] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)]) * np.r_[d, 1]
    return (T @ pts.T).T[:, :3]


class Cam:
    def __init__(self, c):
        self.T = mat(c["transform"]); self.R = self.T[:3, :3]; self.t = self.T[:3, 3]
        self.fx, self.fy, self.cx, self.cy = c["fx"], c["fy"], c["cx"], c["cy"]
        self.W, self.H = c["width"], c["height"]

    def to_cam(self, p):
        return (p - self.t) @ self.R  # R^T (p - t)

    def project(self, p):
        c = self.to_cam(np.atleast_2d(p)); depth = -c[:, 2]
        u = self.fx * c[:, 0] / depth + self.cx; v = self.fy * -c[:, 1] / depth + self.cy
        return u, v, depth


class Box:
    """Oriented box for ray occlusion tests (objects and wall slabs)."""
    def __init__(self, id_, T, d):
        self.id = id_; self.Ti = np.linalg.inv(T); self.h = np.maximum(np.array(d, np.float64), 0.05) / 2
        self.holes = []

    def contains(self, p, margin=0.1):
        q = self.Ti[:3, :3] @ p + self.Ti[:3, 3]
        return bool((np.abs(q) <= self.h + margin).all())

    def hit_before(self, a, b, slack=0.05):
        """Does segment a->b (world) enter this box before the last `slack` m?"""
        A = self.Ti[:3, :3] @ a + self.Ti[:3, 3]; B = self.Ti[:3, :3] @ b + self.Ti[:3, 3]
        dvec = B - A; L = np.linalg.norm(dvec)
        if L < 1e-6: return False
        t0, t1 = 0.0, max(0.0, 1 - slack / L)
        for k in range(3):
            if abs(dvec[k]) < 1e-9:
                if abs(A[k]) > self.h[k]: return False
                continue
            ta = (-self.h[k] - A[k]) / dvec[k]; tb = (self.h[k] - A[k]) / dvec[k]
            if ta > tb: ta, tb = tb, ta
            t0, t1 = max(t0, ta), min(t1, tb)
            if t0 > t1: return False
        if self.holes:  # a wall: the ray may pass through a door/window opening
            p = a + (b - a) * (t0 + 1e-3)
            if any(h.contains(p, margin=0.05) for h in self.holes): return False
        return True


def load_scan(scan):
    g = json.load(open(f"{BENCH}/ipad_raw/{scan}/geometry.json"))
    cams = [Cam(c) for c in json.load(open(f"{FRAMES}/{scan}/frames/cameras.json"))]
    boxes = [Box(o["id"], mat(o["transform"]), o["dimensions"]) for o in g["objects"]]
    holes = [Box(o["id"], mat(o["transform"]), [o["dimensions"][0], o["dimensions"][1], 0.4]) for o in g.get("openings", [])]
    for w in g["walls"]:
        b = Box(w["id"], mat(w["transform"]), [w["dimensions"][0], w["dimensions"][1], 0.05]); b.holes = holes
        boxes.append(b)
    return g, cams, boxes


def sample_points(obj, n=3):
    """Points on the box surface-ish: a grid inside the box (shrunk 0.8) -> used for visibility rays."""
    T = mat(obj["transform"]); d = np.array(obj["dimensions"], np.float64) * 0.8
    g = np.linspace(-.5, .5, n)
    pts = np.array([[x, y, z, 1] for x in g for y in g for z in g]) * np.r_[d, 1]
    return (T @ pts.T).T[:, :3]


def candidate(obj, cam, boxes):
    """CropPicker-like candidate in this frame, sensor pixels. None if any corner is behind the camera."""
    u, v, dep = cam.project(corners(obj))
    if (dep < 0.1).any(): return None
    x0, x1, y0, y1 = u.min(), u.max(), v.min(), v.max()
    area = (x1 - x0) * (y1 - y0)
    if area <= 0: return None
    cx0, cx1, cy0, cy1 = max(x0, 0), min(x1, cam.W), max(y0, 0), min(y1, cam.H)
    if cx1 <= cx0 or cy1 <= cy0: return None
    visible = (cx1 - cx0) * (cy1 - cy0) / area
    # occlusion: rays from camera to interior points; blocked by another object box or a wall slab
    pts = sample_points(obj)
    pu, pv, pd = cam.project(pts)
    inimg = (pd > 0.1) & (pu >= 0) & (pu < cam.W) & (pv >= 0) & (pv < cam.H)
    # a box the camera stands in (e.g. a false "storage" box in a doorway) can't hide anything
    blockers = [b for b in boxes if b.id != obj["id"] and not b.contains(cam.t)]
    hits = tot = 0
    for p, ok in zip(pts, inimg):
        if not ok: continue
        tot += 1
        if any(b.hit_before(cam.t, p) for b in blockers): hits += 1
    occluded = hits / tot if tot else 1.0
    rect = (cx0 / cam.W, cy0 / cam.H, (cx1 - cx0) / cam.W, (cy1 - cy0) / cam.H)  # sensor-normalized
    return dict(full=(x0, y0, x1, y1), rect=rect, visible=visible, occluded=occluded, distance=float(dep.min()),
                area=rect[2] * rect[3])


def lap_var(img):
    a = np.asarray(img.convert("L"), np.float64)
    if a.shape[0] < 3 or a.shape[1] < 3: return 0.0
    l = 4 * a[1:-1, 1:-1] - a[:-2, 1:-1] - a[2:, 1:-1] - a[1:-1, :-2] - a[1:-1, 2:]
    return float(l.var())


def score(c, sharp, typical):
    """CropPicker.score with the depth-occlusion replaced by box-ray occlusion."""
    if c["visible"] < 0.7 or c["occluded"] > 0.4 or c["area"] < 0.01 or c["distance"] < 0.3: return 0.0
    size = min(c["area"] / 0.2, 1); clip = c["visible"] ** 3; clear = (1 - c["occluded"]) ** 2
    s = min(max(sharp / typical, .25), 1.25) if typical > 0 else 1
    x, y, w, h = c["rect"]; off = np.hypot(x + w / 2 - .5, y + h / 2 - .5)
    return size * clip * clear * s * (1 - .5 * off)


def crop(img, c, pad, min_side=0.2):
    """Crop the (clipped) projected rect scaled by `pad`, min `min_side` of the frame, shifted inside;
    returned upright (rotated 90 deg clockwise like the app's photos)."""
    W, H = img.size; x, y, w, h = c["rect"]
    cw = min(max(w * pad, min_side), 1); ch = min(max(h * pad, min_side), 1)
    nx = min(max(x + w / 2 - cw / 2, 0), 1 - cw); ny = min(max(y + h / 2 - ch / 2, 0), 1 - ch)
    box = (int(round(nx * W)), int(round(ny * H)), int(round((nx + cw) * W)), int(round((ny + ch) * H)))
    return img.crop(box).transpose(Image.ROTATE_270)
