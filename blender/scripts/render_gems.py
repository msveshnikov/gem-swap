"""Render the Gem Swap gem sprites with Cycles.

blender -b --factory-startup -P blender/scripts/render_gems.py [-- --quick] [-- --only ruby]

Every gem is a faceted solid built from a 2D outline (crown table, star facets, girdle, pavilion, culet).
Each one is rendered FRAMES times while the light rig turns around it, so the game can flick through the
frames for a real moving glint. Output: assets/gems/<name>.png = horizontal strip FRAMES x SIZE.
"""
import bpy, bmesh, math, os, sys, colorsys
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "gems")
TMP = os.path.join(ROOT, "renders", "blender", "frames")
SIZE = 192
FRAMES = 8

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
QUICK = "--quick" in argv
ONLY = argv[argv.index("--only") + 1] if "--only" in argv else ""


# ------------------------------------------------------------------ outlines (max radius ~1)

def poly(n, r=1.0, rot=0.0, sx=1.0, sy=1.0):
    return [(math.cos(rot + i * math.tau / n) * r * sx, math.sin(rot + i * math.tau / n) * r * sy) for i in range(n)]


def chamfer(pts, cut):
    """Cut every corner of a polygon (cut = fraction of each edge)."""
    out = []
    n = len(pts)
    for i in range(n):
        p, a, b = Vector(pts[i]), Vector(pts[i - 1]), Vector(pts[(i + 1) % n])
        out.append(tuple(p.lerp(a, cut)))
        out.append(tuple(p.lerp(b, cut)))
    return out


def star(points=5, r_out=1.0, r_in=0.55):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.pi / 2 + i * math.pi / points
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def heart(n=28):
    pts = []
    for i in range(n):
        t = i / n * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 17.0, (y + 2.5) / 17.0))
    return pts


GEMS = [
    # name, outline, colour (linear-ish sRGB), table, crown, pavilion, ior
    ("ruby",     chamfer(poly(4, 1.0, math.pi / 4, 0.98, 0.98), 0.22), (0.95, 0.05, 0.12), 0.56, 0.30, 0.62, 1.76),
    ("topaz",    poly(6, 1.0, math.pi / 6),                         (1.00, 0.42, 0.03), 0.52, 0.30, 0.60, 1.62),
    ("citrine",  chamfer(poly(3, 1.08, math.pi / 2), 0.12),         (1.00, 0.82, 0.05), 0.48, 0.28, 0.58, 1.55),
    ("emerald",  chamfer(poly(4, 1.0, math.pi / 4, 0.80, 1.02), 0.2), (0.04, 0.85, 0.30), 0.62, 0.22, 0.50, 1.58),
    ("sapphire", poly(16, 0.98),                                    (0.06, 0.32, 1.00), 0.55, 0.32, 0.66, 1.77),
    ("amethyst", poly(4, 1.0, math.pi / 2, 0.74, 1.04),             (0.62, 0.12, 0.95), 0.50, 0.30, 0.62, 1.55),
    ("diamond",  star(5, 1.06, 0.58),                               (0.80, 0.95, 1.00), 0.50, 0.30, 0.60, 2.42),
    ("rose",     heart(),                                           (1.00, 0.30, 0.65), 0.55, 0.28, 0.55, 1.60),
    ("prism",    poly(20, 1.0),                                     None,               0.42, 0.42, 0.70, 2.0),
]


# ------------------------------------------------------------------ scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
    except TypeError:
        pass
    sc.cycles.samples = 24 if QUICK else 96
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 16
    sc.cycles.transmission_bounces = 14
    sc.cycles.glossy_bounces = 8
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_refractive = True
    sc.render.film_transparent = True
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    except TypeError:
        pass
    sc.view_settings.exposure = -0.35
    # world: dark studio, bright gradient visible only in reflections/refractions
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    cr = ramp.color_ramp
    cr.elements[0].position = 0.05
    cr.elements[0].color = (0.01, 0.01, 0.015, 1)
    cr.elements[1].position = 0.95
    cr.elements[1].color = (0.03, 0.03, 0.04, 1)
    for pos, v in ((0.3, 1.6), (0.55, 0.9), (0.72, 0.08)):
        e = cr.elements.new(pos)
        e.color = (v, v, v * 1.05, 1)
    nt.links.new(ramp.outputs[0], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    # camera straight down
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.36
    cam.location = (0, 0, 10)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # light rig (rotated per frame)
    rig = bpy.data.objects.new("Rig", None)
    sc.collection.objects.link(rig)
    def area(name, loc, power, size, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = power
        ld.size = size
        ld.color = color
        o = bpy.data.objects.new(name, ld)
        o.location = loc
        d = Vector((0, 0, 0)) - Vector(loc)
        o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        o.parent = rig
        sc.collection.objects.link(o)
    area("Key", (-3.0, 3.2, 5.0), 420, 2.2)
    area("Rim", (3.6, -2.2, 2.2), 260, 1.4, (0.85, 0.92, 1.0))
    area("Top", (2.2, -1.6, 6.0), 70, 1.5)
    area("Kick", (2.5, 3.5, 1.2), 160, 0.6, (1.0, 0.95, 0.85))
    # emissive "softbox" strips seen only in the facets (no camera rays)
    for i, (x, y, z, rx, s) in enumerate([(-2.2, 2.5, 3.5, 0.6, 1.2), (2.8, 1.0, 3.0, -0.5, 0.8), (0.5, -3.0, 2.6, 0.9, 0.9)]):
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(x, y, z))
        p = bpy.context.active_object
        p.scale = (s * 2.6, s * 0.5, 1)
        p.rotation_euler = (rx, -x * 0.25, math.atan2(y, x))
        m = bpy.data.materials.new("Soft%d" % i)
        m.use_nodes = True
        nn = m.node_tree.nodes
        for n in list(nn):
            if n.type != "OUTPUT_MATERIAL":
                nn.remove(n)
        em = nn.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 6.0
        tr = nn.new("ShaderNodeBsdfTransparent")
        lp = nn.new("ShaderNodeLightPath")
        mix = nn.new("ShaderNodeMixShader")
        lk = m.node_tree.links
        lk.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
        lk.new(em.outputs[0], mix.inputs[1])
        lk.new(tr.outputs[0], mix.inputs[2])
        lk.new(mix.outputs[0], next(n for n in nn if n.type == "OUTPUT_MATERIAL").inputs[0])
        p.data.materials.append(m)
        p.visible_camera = False
        p.visible_shadow = False
        p.parent = rig
    return rig


def build_gem(outline, table, crown, pav, name):
    mx = max(max(abs(x) for x, y in outline), max(abs(y) for x, y in outline))
    cy = (max(y for x, y in outline) + min(y for x, y in outline)) * 0.5
    outline = [(x / mx, (y - cy) / mx) for x, y in outline]
    bm = bmesh.new()
    n = len(outline)
    rings = []
    def ring(scale, z, twist=0.0):
        vs = []
        for i in range(n):
            x, y = outline[i]
            if twist:
                x2, y2 = outline[(i + 1) % n]
                x, y = x + (x2 - x) * twist, y + (y2 - y) * twist
            vs.append(bm.verts.new((x * scale, y * scale, z)))
        return vs
    g = 0.035
    r_table = ring(table, crown)
    r_star = ring((1 + table) * 0.5 + 0.06, crown * 0.55, 0.5)
    r_gt = ring(1.0, g)
    r_gb = ring(1.0, -g)
    r_pav = ring(0.52, -pav * 0.55, 0.5)
    culet = bm.verts.new((0, 0, -pav))
    bm.faces.new(r_table)
    def bridge(a, b):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[i]))
            bm.faces.new((a[j], b[j], b[i]))
    bridge(r_table, r_star)
    bridge(r_star, r_gt)
    bridge(r_gt, r_gb)
    bridge(r_gb, r_pav)
    for i in range(n):
        bm.faces.new((r_pav[(i + 1) % n], r_pav[i], culet))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def gem_material(color, ior, rainbow=False):
    m = bpy.data.materials.new("Gem")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    def setin(name, v):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = v
    setin("Roughness", 0.015)
    setin("IOR", ior)
    setin("Transmission Weight", 1.0)
    setin("Transmission", 1.0)
    setin("Specular IOR Level", 0.8)
    setin("Dispersion", 0.6 if rainbow else 0.25)
    if rainbow:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        math_n = nt.nodes.new("ShaderNodeMath")
        math_n.operation = "ARCTAN2"
        div = nt.nodes.new("ShaderNodeMath")
        div.operation = "MULTIPLY_ADD"
        div.inputs[1].default_value = 1.0 / math.tau
        div.inputs[2].default_value = 0.5
        hsv = nt.nodes.new("ShaderNodeCombineColor")
        hsv.mode = "HSV"
        hsv.inputs[1].default_value = 0.85
        hsv.inputs[2].default_value = 1.0
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        nt.links.new(sep.outputs["Y"], math_n.inputs[0])
        nt.links.new(sep.outputs["X"], math_n.inputs[1])
        nt.links.new(math_n.outputs[0], div.inputs[0])
        nt.links.new(div.outputs[0], hsv.inputs[0])
        nt.links.new(hsv.outputs[0], bsdf.inputs["Base Color"])
        if "Emission Color" in bsdf.inputs:
            nt.links.new(hsv.outputs[0], bsdf.inputs["Emission Color"])
        setin("Emission Strength", 0.35)
    else:
        c = (*color, 1.0)
        setin("Base Color", c)
        setin("Emission Color", c)
        setin("Emission Strength", 0.4 if color != (0.80, 0.95, 1.00) else 0.04)
        # coloured volume gives depth: thicker parts get richer
        vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
        vol.inputs["Color"].default_value = c
        vol.inputs["Density"].default_value = 0.0 if color == (0.80, 0.95, 1.00) else 2.6
        nt.links.new(vol.outputs[0], out.inputs["Volume"])
    return m


def render_strip(name, obj):
    sc = bpy.context.scene
    rig = bpy.data.objects["Rig"]
    os.makedirs(TMP, exist_ok=True)
    paths = []
    for f in range(FRAMES):
        rig.rotation_euler = (0, 0, f * math.tau / FRAMES)
        p = os.path.join(TMP, "%s_%d.png" % (name, f))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    # stitch
    strip = bpy.data.images.new(name + "_strip", SIZE * FRAMES, SIZE, alpha=True)
    px = [0.0] * (SIZE * FRAMES * SIZE * 4)
    for f, p in enumerate(paths):
        im = bpy.data.images.load(p)
        src = list(im.pixels)
        for y in range(SIZE):
            row = y * SIZE * 4
            dst = (y * SIZE * FRAMES + f * SIZE) * 4
            px[dst:dst + SIZE * 4] = src[row:row + SIZE * 4]
        bpy.data.images.remove(im)
    strip.pixels = px
    strip.filepath_raw = os.path.join(OUT, name + ".png")
    strip.file_format = "PNG"
    strip.save()
    print("WROTE", strip.filepath_raw)


def stone():
    """A chunky carved stone block (obstacle), one frame."""
    bpy.ops.mesh.primitive_cube_add(size=1.7)
    o = bpy.context.active_object
    bev = o.modifiers.new("b", "BEVEL")
    bev.width = 0.22
    bev.segments = 3
    sub = o.modifiers.new("s", "SUBSURF")
    sub.levels = 3
    sub.render_levels = 3
    tex = bpy.data.textures.new("n", "VORONOI")
    tex.noise_scale = 0.32
    disp = o.modifiers.new("d", "DISPLACE")
    disp.texture = tex
    disp.strength = -0.22
    tex2 = bpy.data.textures.new("n2", "CLOUDS")
    tex2.noise_scale = 0.18
    disp2 = o.modifiers.new("d2", "DISPLACE")
    disp2.texture = tex2
    disp2.strength = 0.07
    m = bpy.data.materials.new("Stone")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.05, 0.045, 0.06, 1)
    ramp.color_ramp.elements[1].color = (0.30, 0.26, 0.30, 1)
    nt.links.new(noise.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    nt.links.new(noise.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    o.data.materials.append(m)
    o.rotation_euler = (0.25, -0.2, 0.1)
    o.scale = (0.95, 0.95, 0.95)
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(OUT, "stone.png")
    bpy.ops.render.render(write_still=True)
    print("WROTE stone")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, outline, col, table, crown, pav, ior in GEMS:
        if ONLY and name != ONLY:
            continue
        reset()
        o = build_gem(outline, table, crown, pav, name)
        o.data.materials.append(gem_material(col, ior, rainbow=(col is None)))
        render_strip(name, o)
    if not ONLY or ONLY == "stone":
        reset()
        stone()


main()
