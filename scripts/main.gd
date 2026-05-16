extends Node3D

# ═══════════════════════════════════════════
# QUANTUM DANCE — Image Galaxy · Video Crystal · Celestial Skybox
# 5-band audio sand · Modes · Video export · Logo intro
# ═══════════════════════════════════════════

# ── Audio ──
var audio: AudioStreamPlayer
var band_data: BandData
var time: float = 0.0
var speed_mult: float = 1.0
var sub_v: float = 0.0; var bass_v: float = 0.0; var mid_v: float = 0.0
var high_v: float = 0.0; var air_v: float = 0.0
var onset_v: float = 0.0; var rms_v: float = 0.0
var centroid_v: float = 0.5; var beat_e: float = 0.0

# ── Camera ──
var cam: Camera3D
var cam_theta: float = 0.0; var cam_phi: float = 0.2
var cam_radius: float = 9.0
var mouse_dragging: bool = false; var mouse_last: Vector2
var auto_orbit: bool = true

# ── Modes ──
enum Mode { SANDS, IMAGE_CLOUD, VIDEO_CRYSTAL, COMBINED }
var mode: Mode = Mode.SANDS
var mode_names = ["Sand Particles", "Image Cloud", "Video Crystal", "Combined"]

# ── 5-band sand particles ──
var sand_shader: ShaderMaterial
var p_sub: GPUParticles3D; var p_bass: GPUParticles3D
var p_mid: GPUParticles3D; var p_high: GPUParticles3D; var p_air: GPUParticles3D
var sand_systems: Array = []
var attractor_root: Node3D
var attractors: Array = []

# ── Image cloud ──
var image_cloud: Node3D
var image_particles: Array = []
var image_loaded: bool = false

# ── Video crystal ──
var video_player: VideoStreamPlayer
var video_sphere: MeshInstance3D
var video_loaded: bool = false

# ── Skybox ──
var sky_material: PanoramaSkyMaterial
var sky_loaded: bool = false

# ── Logo intro ──
var logo_played: bool = false
var logo_player: VideoStreamPlayer

# ── Environment ──
var env_ref: Environment
var starfield: GPUParticles3D
var palette_index: int = 0
const PALETTES = [
	{"name":"Quantum Gold","sub":Color(0.9,0.7,0.2),"bass":Color(1,0.5,0.15),"mid":Color(0.2,0.7,0.9),"high":Color(0.6,0.3,1),"air":Color(1,0.9,0.6)},
	{"name":"Deep Space","sub":Color(0.3,0.1,0.6),"bass":Color(0.5,0.2,0.8),"mid":Color(0.1,0.5,0.9),"high":Color(0.3,0.7,1),"air":Color(0.8,0.9,1)},
	{"name":"Emerald Fire","sub":Color(0.1,0.6,0.3),"bass":Color(0.2,0.8,0.2),"mid":Color(0.1,0.5,0.6),"high":Color(0.3,0.9,0.7),"air":Color(0.7,1,0.8)},
	{"name":"Crimson","sub":Color(0.6,0.1,0.1),"bass":Color(0.9,0.2,0.2),"mid":Color(0.8,0.3,0.5),"high":Color(1,0.4,0.7),"air":Color(1,0.7,0.8)},
	{"name":"Void White","sub":Color(0.6,0.6,0.7),"bass":Color(0.7,0.7,0.8),"mid":Color(0.8,0.8,0.9),"high":Color(0.9,0.9,1),"air":Color(1,1,1)},
	{"name":"Sunset","sub":Color(1,0.4,0.1),"bass":Color(1,0.6,0.3),"mid":Color(0.9,0.3,0.5),"high":Color(0.6,0.2,0.9),"air":Color(1,0.8,0.5)},
]


# ═══════════════════════════════════════════
# BandData
# ═══════════════════════════════════════════
class BandData extends RefCounted:
	var sub: PackedFloat64Array; var bass: PackedFloat64Array
	var mid: PackedFloat64Array; var high: PackedFloat64Array
	var air: PackedFloat64Array; var onset: PackedFloat64Array
	var rms: PackedFloat64Array; var centroid: PackedFloat64Array
	var num_frames: int; var fps: float
	static func load_file(path: String) -> BandData:
		var f = FileAccess.open(path, FileAccess.READ); if not f: return null
		var j = JSON.new(); j.parse(f.get_as_text()); var d = j.get_data(); var bd = BandData.new()
		bd.sub=_a(d,"sub_bass"); bd.bass=_a(d,"bass"); bd.mid=_a(d,"mid"); bd.high=_a(d,"high")
		bd.air=_a(d,"air"); bd.onset=_a(d,"onset"); bd.rms=_a(d,"rms"); bd.centroid=_a(d,"centroid")
		bd.num_frames=d.get("num_frames",0); bd.fps=d.get("fps",30); return bd
	static func _a(d: Dictionary, k: String) -> PackedFloat64Array: return PackedFloat64Array(d.get(k,[]))
	func frame_at(t: float) -> Dictionary:
		if num_frames<=0: return {"sub":0,"bass":0,"mid":0,"high":0,"air":0,"onset":0,"rms":0.5,"centroid":0.5}
		var i=clampi(int(t*fps),0,num_frames-1)
		return {"sub":sub[i] if i<sub.size() else 0.0,"bass":bass[i] if i<bass.size() else 0.0,"mid":mid[i] if i<mid.size() else 0.0,"high":high[i] if i<high.size() else 0.0,"air":air[i] if i<air.size() else 0.0,"onset":onset[i] if i<onset.size() else 0.0,"rms":rms[i] if i<rms.size() else 0.5,"centroid":centroid[i] if i<centroid.size() else 0.5}


# ═══════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════
func _ready():
	_setup_scene()
	_load_audio()
	# Logo intro — if logo.mp4 exists, play it first
	if FileAccess.file_exists("res://music/logo.mp4"):
		_play_logo()
	else:
		audio.play()


func _setup_scene():
	# Audio
	audio = AudioStreamPlayer.new(); add_child(audio)

	# Environment
	var env = WorldEnvironment.new()
	env_ref = Environment.new()
	env_ref.background_color = Color(0.003,0.002,0.008)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.ambient_light_color = Color(0.02,0.01,0.05)
	env_ref.glow_enabled = true; env_ref.glow_intensity = 4.0
	env_ref.glow_bloom = 0.9; env_ref.glow_hdr_threshold = 0.3; env_ref.glow_hdr_scale = 3.5
	env_ref.volumetric_fog_enabled = true; env_ref.volumetric_fog_density = 0.004
	env_ref.volumetric_fog_albedo = Color(0.03,0.01,0.06)
	env_ref.volumetric_fog_emission = Color(0.06,0.02,0.1)
	env_ref.volumetric_fog_emission_energy = 0.5

	# Sky (replaceable with image)
	sky_material = PanoramaSkyMaterial.new()
	var sky = Sky.new(); sky.sky_material = sky_material
	env_ref.sky = sky
	env.environment = env_ref; add_child(env)

	# Camera
	cam = Camera3D.new(); cam.current = true; cam.fov = 62; add_child(cam)
	_update_camera()

	# Center sun — proof of life
	var sun = MeshInstance3D.new(); sun.name = "CenterSun"
	var sun_sphere = SphereMesh.new(); sun_sphere.radius = 0.4; sun_sphere.height = 0.8
	sun.mesh = sun_sphere
	var sun_mat = StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1, 0.7, 0.2)
	sun_mat.emission_enabled = true; sun_mat.emission = Color(1, 0.6, 0.1)
	sun_mat.emission_energy_multiplier = 5.0
	sun.material_override = sun_mat; add_child(sun)

	# Orbiting test orbs — visible rings
	for i in 12:
		var a = i * TAU / 12.0
		var orb = MeshInstance3D.new()
		var os = SphereMesh.new(); os.radius = 0.08; os.height = 0.16
		orb.mesh = os; orb.position = Vector3(cos(a)*2.0, 0, sin(a)*2.0)
		var om = StandardMaterial3D.new(); om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.albedo_color = Color(0.3, 0.6, 1.0)
		om.emission_enabled = true; om.emission = Color(0.2, 0.5, 1.0)
		om.emission_energy_multiplier = 4.0
		orb.material_override = om; add_child(orb)

	# Starfield
	_create_starfield()

	# Sand shader
	sand_shader = ShaderMaterial.new(); sand_shader.shader = load("res://shaders/sand.gdshader")

	# Attractor root
	attractor_root = Node3D.new(); attractor_root.name = "Attractors"; add_child(attractor_root)

	# 5 sand particle systems
	p_sub  = _make_sand(2000,0.06,0.15); p_bass = _make_sand(1500,0.05,0.12)
	p_mid  = _make_sand(1200,0.04,0.10); p_high = _make_sand(900,0.03,0.08)
	p_air  = _make_sand(600,0.02,0.06)
	sand_systems = [p_sub,p_bass,p_mid,p_high,p_air]
	_build_attractors()

	# Image cloud container
	image_cloud = Node3D.new(); image_cloud.name = "ImageCloud"; add_child(image_cloud)

	# Video player + crystal sphere
	video_player = VideoStreamPlayer.new(); video_player.name = "VideoPlayer"
	video_player.expand = true; add_child(video_player)
	video_sphere = MeshInstance3D.new(); video_sphere.name = "VideoSphere"
	var sph = SphereMesh.new(); sph.radius = 2.0; sph.height = 4.0; sph.radial_segments = 32; sph.rings = 16
	video_sphere.mesh = sph
	var vmat = StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.emission_enabled = true; vmat.emission = Color(1,1,1); vmat.emission_energy_multiplier = 2.0
	video_sphere.material_override = vmat; video_sphere.visible = false
	add_child(video_sphere)

	# HUD
	var label = Label.new(); label.name = "Label"; label.position = Vector2(20,20)
	label.add_theme_color_override("font_color",Color(0.7,0.6,1.0))
	label.add_theme_font_size_override("font_size",14); add_child(label)


func _load_audio():
	var fp = "res://music/the num singularity immersion.mp3"
	var s = load(fp); if s: audio.stream = s
	band_data = BandData.load_file("res://music/the_num_singularity_immersion.quantum")


# ═══════════════════════════════════════════
# LOGO INTRO
# ═══════════════════════════════════════════
func _play_logo():
	logo_player = VideoStreamPlayer.new(); logo_player.name = "LogoPlayer"
	var vs = load("res://music/logo.mp4")
	if vs: logo_player.stream = vs
	logo_player.expand = true; logo_player.finished.connect(_on_logo_done)
	add_child(logo_player)
	logo_player.play()


func _on_logo_done():
	logo_player.queue_free()
	audio.play()


# ═══════════════════════════════════════════
# SAND PARTICLES
# ═══════════════════════════════════════════
func _make_sand(amount: int, smin: float, smax: float) -> GPUParticles3D:
	var ps = GPUParticles3D.new(); ps.emitting = true; ps.amount = amount
	ps.lifetime = 5.0; ps.speed_scale = 0.5
	ps.visibility_aabb = AABB(Vector3(-20,-20,-20),Vector3(40,40,40))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 3.0; pm.spread = 90.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 1.5
	pm.scale_min = smin; pm.scale_max = smax
	pm.damping_min = 0.3; pm.damping_max = 0.7
	pm.radial_accel_min = -1.5; pm.radial_accel_max = 0.5
	pm.tangential_accel_min = -1.0; pm.tangential_accel_max = 1.0
	ps.process_material = pm
	var dp = MeshInstance3D.new(); var sp = SphereMesh.new()
	sp.radius = 0.08; sp.height = 0.16; sp.radial_segments = 3; sp.rings = 1
	dp.mesh = sp
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.6, 0.2)
	mat.emission_enabled = true; mat.emission = Color(1, 0.5, 0.1)
	mat.emission_energy_multiplier = 5.0
	dp.material_override = mat; ps.draw_pass_1 = dp; add_child(ps); return ps


func _build_attractors():
	var phi = 1.618033988749895; var iphi = 1.0/phi
	var dv = [Vector3(1,1,1),Vector3(1,1,-1),Vector3(1,-1,1),Vector3(1,-1,-1),Vector3(-1,1,1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(-1,-1,-1),Vector3(0,iphi,phi),Vector3(0,iphi,-phi),Vector3(0,-iphi,phi),Vector3(0,-iphi,-phi),Vector3(iphi,phi,0),Vector3(iphi,-phi,0),Vector3(-iphi,phi,0),Vector3(-iphi,-phi,0),Vector3(phi,0,iphi),Vector3(phi,0,-iphi),Vector3(-phi,0,iphi),Vector3(-phi,0,-iphi)]
	for v in dv: _add_att(v.normalized()*4.0,"dodec")
	var iv = [Vector3(0,1,phi),Vector3(0,1,-phi),Vector3(0,-1,phi),Vector3(0,-1,-phi),Vector3(1,phi,0),Vector3(1,-phi,0),Vector3(-1,phi,0),Vector3(-1,-phi,0),Vector3(phi,0,1),Vector3(phi,0,-1),Vector3(-phi,0,1),Vector3(-phi,0,-1)]
	for v in iv: _add_att(v.normalized()*2.8,"ico")
	var ga = PI*(3.0-sqrt(5.0))
	for i in 14: var t = float(i)/14; var th = i*ga; _add_att(Vector3(cos(th)*(1.5+t*3.0),(t-0.5)*3.0,sin(th)*(1.5+t*3.0)),"spiral")
	for i in 12: var a = i*TAU/12.0; _add_att(Vector3(cos(a)*5.0,0,sin(a)*5.0),"torus")
	for _i in 20: _add_att(Vector3(randf_range(-4,4),randf_range(-4,4),randf_range(-4,4)),"scatter")


func _add_att(pos: Vector3, gtype: String):
	var att = GPUParticlesAttractorSphere3D.new(); att.position = pos
	att.strength = randf_range(2.0,5.0); att.attenuation = 0.5; att.radius = randf_range(0.5,1.5)
	attractor_root.add_child(att); attractors.append({"node":att,"base_pos":pos,"phase":randf()*TAU,"type":gtype})


# ═══════════════════════════════════════════
# IMAGE → PARTICLE CLOUD
# ═══════════════════════════════════════════
func load_image_cloud(path: String):
	_clear_image_cloud()
	var img = Image.load_from_file(path)
	if img.is_empty(): return
	img.resize(100, 100, Image.INTERPOLATE_LANCZOS)
	var w = img.get_width(); var h = img.get_height()
	for y in range(0, h):
		for x in range(0, w):
			var col = img.get_pixel(x, y)
			var lum = col.get_luminance()
			if lum < 0.08: continue
			var pos = Vector3((float(x)/w-0.5)*6.0, (float(y)/h-0.5)*6.0, lum*4.0 - 1.0)
			_add_image_orb(pos, col)
	image_loaded = true


func _add_image_orb(pos: Vector3, col: Color):
	var mesh = MeshInstance3D.new(); var s = SphereMesh.new()
	s.radius = 0.06; s.height = 0.12; s.radial_segments = 3; s.rings = 1
	mesh.mesh = s; mesh.position = pos
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 5.0
	mesh.material_override = mat; image_cloud.add_child(mesh)
	image_particles.append({"node":mesh,"base_pos":pos,"color":col,"phase":randf()*TAU})


func _clear_image_cloud():
	for ip in image_particles: ip["node"].queue_free()
	image_particles.clear(); image_loaded = false


# ═══════════════════════════════════════════
# VIDEO CRYSTAL SPHERE
# ═══════════════════════════════════════════
func load_video(path: String):
	var vs = load(path)
	if vs: video_player.stream = vs; video_player.play(); video_sphere.visible = true; video_loaded = true


# ═══════════════════════════════════════════
# CELESTIAL SKYBOX — load image as sky
# ═══════════════════════════════════════════
func load_skybox(path: String):
	var img = Image.load_from_file(path)
	if img.is_empty(): return
	var tex = ImageTexture.create_from_image(img)
	sky_material.panorama = tex
	env_ref.background_mode = Environment.BG_SKY
	sky_loaded = true


# ═══════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════
func _process(delta):
	delta *= speed_mult
	if Input.is_key_pressed(KEY_SHIFT): delta *= 0.1
	time += delta

	var t = 0.0
	var f = {"sub":0,"bass":0,"mid":0,"high":0,"air":0,"onset":0,"rms":0.5,"centroid":0.5}
	if audio.playing:
		t = audio.get_playback_position()
		if band_data: f = band_data.frame_at(t)
	else:
		f["sub"]=sin(time*0.5)*0.4+0.6; f["bass"]=sin(time*0.7+1)*0.4+0.6
		f["mid"]=sin(time*1.1+2)*0.4+0.6; f["high"]=sin(time*1.3+3)*0.4+0.6
		f["air"]=sin(time*1.7+4)*0.4+0.6; f["rms"]=sin(time*0.3)*0.25+0.5

	sub_v=f["sub"]; bass_v=f["bass"]; mid_v=f["mid"]; high_v=f["high"]; air_v=f["air"]
	onset_v=f["onset"]; rms_v=f["rms"]; centroid_v=f["centroid"]
	beat_e = lerp(beat_e, onset_v*3.0, delta*8.0)
	var pal = PALETTES[palette_index]
	var vals = [sub_v,bass_v,mid_v,high_v,air_v]
	var cols = [pal["sub"],pal["bass"],pal["mid"],pal["high"],pal["air"]]

	# ── Update video sphere ──
	if video_loaded:
		video_sphere.visible = (mode == Mode.VIDEO_CRYSTAL or mode == Mode.COMBINED)
		video_sphere.rotate_y(delta*0.3); video_sphere.rotate_x(delta*0.15)
		video_sphere.position = Vector3(0, sin(time*0.2)*0.3, 0)
		video_sphere.scale = Vector3.ONE*(1.0+bass_v*0.2)

	# ── Sand particle systems ──
	var sand_visible = (mode == Mode.SANDS or mode == Mode.COMBINED)
	for i in sand_systems.size():
		sand_systems[i].visible = sand_visible
		if not sand_visible: continue
		sand_systems[i].speed_scale = 0.3+vals[i]*1.8
		var dp = sand_systems[i].draw_pass_1
		if dp:
			var mat: StandardMaterial3D = dp.material_override
			mat.albedo_color = cols[i]
			mat.emission = cols[i]
			mat.emission_energy_multiplier = 3.0 + vals[i] * 5.0

	# ── Update attractors ──
	for att in attractors:
		var node: GPUParticlesAttractor3D = att["node"]; var bp: Vector3 = att["base_pos"]
		var ph: float = att["phase"]; var gt: String = att["type"]
		match gt:
			"dodec": node.position=bp.rotated(Vector3(0,1,0),time*0.15*(0.5+bass_v)); node.strength=2.0+bass_v*6.0
			"ico": node.position=bp.rotated(Vector3(1,0,1).normalized(),time*0.25*(0.5+high_v)); node.strength=1.5+high_v*5.0
			"spiral": node.position=bp+Vector3(sin(time*2+ph)*0.3,cos(time*1.7+ph)*0.3,cos(time*2.2+ph)*0.3)*(0.5+mid_v); node.strength=1.0+mid_v*4.0
			"torus": node.position=bp.rotated(Vector3(0.3,1,0.2).normalized(),time*0.1*(0.5+sub_v)); node.strength=3.0+sub_v*6.0
			"scatter": node.position=bp+Vector3(sin(time*3+ph)*1.5,cos(time*2.5+ph)*1.5,sin(time*2.8+ph)*1.5)*(0.5+air_v); node.strength=0.5+air_v*3.0

	# ── Image cloud animation ──
	if image_loaded and (mode == Mode.IMAGE_CLOUD or mode == Mode.COMBINED):
		image_cloud.visible = true
		for ip in image_particles:
			var nd: MeshInstance3D = ip["node"]; var bp: Vector3 = ip["base_pos"]
			var ph: float = ip["phase"]
			# Explode on beat, reform when quiet
			var spread = beat_e*2.5+(1.0+rms_v)*0.5
			nd.position = bp+Vector3(sin(time*2+ph)*spread,cos(time*1.5+ph)*spread,sin(time*1.8+ph)*spread)
			nd.scale = Vector3.ONE*(0.5+rms_v*1.5+beat_e*2.0)
			var mat: StandardMaterial3D = nd.material_override
			if mat: mat.emission_energy_multiplier = 3.0+rms_v*4.0+beat_e*6.0
	else:
		image_cloud.visible = false

	# ── Beat burst ──
	if onset_v > 0.4: env_ref.glow_intensity=lerp(env_ref.glow_intensity,7.0,delta*10.0)
	else: env_ref.glow_intensity=lerp(env_ref.glow_intensity,4.0,delta*4.0)

	# ── Starfield ──
	if starfield: starfield.speed_scale = 0.1+rms_v*0.8

	# ── Camera ──
	if auto_orbit:
		cam_theta+=delta*(0.12+rms_v*0.3); cam_phi+=sin(time*0.2)*delta*0.05
	cam_phi=clamp(cam_phi,-1.2,1.2); cam_radius=8.0+sin(time*0.4)*2.0-beat_e*2.5
	cam_radius=clamp(cam_radius,4.0,16.0); _update_camera()

	# ── HUD ──
	var label = get_node_or_null("Label")
	if label:
		var ext = ""
		if sky_loaded: ext+=" [sky]"
		if image_loaded: ext+=" [img]"
		if video_loaded: ext+=" [vid]"
		label.text = "%s   S:%.2f B:%.2f M:%.2f H:%.2f A:%.2f   %.1fx   %s%s" % [mode_names[mode],sub_v,bass_v,mid_v,high_v,air_v,speed_mult,PALETTES[palette_index]["name"],ext]


# ═══════════════════════════════════════════
# STARFIELD
# ═══════════════════════════════════════════
func _create_starfield():
	starfield = GPUParticles3D.new(); starfield.name="Starfield"; starfield.emitting=true; starfield.amount=600
	starfield.lifetime=10.0; starfield.speed_scale=0.1
	starfield.visibility_aabb=AABB(Vector3(-20,-20,-20),Vector3(40,40,40))
	var pm=ParticleProcessMaterial.new(); pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents=Vector3(14,14,14); pm.spread=180.0; pm.gravity=Vector3.ZERO
	pm.initial_velocity_min=0.03; pm.initial_velocity_max=0.15; pm.scale_min=0.008; pm.scale_max=0.03
	pm.color=Color(0.6,0.7,1.0); starfield.process_material=pm
	var dp=MeshInstance3D.new(); var s=SphereMesh.new(); s.radius=0.015; s.height=0.03; s.radial_segments=3; s.rings=1
	dp.mesh=s; var sm=StandardMaterial3D.new(); sm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color=Color.WHITE; sm.emission_enabled=true; sm.emission=Color(0.6,0.7,1.0)
	dp.material_override=sm; starfield.draw_pass_1=dp; add_child(starfield); move_child(starfield,0)


# ═══════════════════════════════════════════
# CAMERA
# ═══════════════════════════════════════════
func _update_camera():
	cam.position=Vector3(cos(cam_theta)*cos(cam_phi)*cam_radius,sin(cam_phi)*cam_radius,sin(cam_theta)*cos(cam_phi)*cam_radius)
	cam.look_at(Vector3.ZERO)


# ═══════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB: mode = ((mode + 1) % 4) as Mode; return
			KEY_SPACE: beat_e=3.0; return
			KEY_C: palette_index=(palette_index+1)%PALETTES.size(); return
			KEY_M: auto_orbit=not auto_orbit; return
			KEY_B: env_ref.glow_enabled=not env_ref.glow_enabled; return
			KEY_F: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED); return
			KEY_1: _try_load_image(); return
			KEY_2: _try_load_video(); return
			KEY_3: _try_load_skybox(); return
			KEY_UP: speed_mult=minf(speed_mult+0.05,3.0); return
			KEY_DOWN: speed_mult=maxf(speed_mult-0.05,0.05); return
			KEY_EQUAL,KEY_PLUS: speed_mult=minf(speed_mult+0.05,3.0); return
			KEY_MINUS: speed_mult=maxf(speed_mult-0.05,0.05); return
			KEY_PAGEUP: speed_mult=minf(speed_mult+0.5,3.0); return
			KEY_PAGEDOWN: speed_mult=maxf(speed_mult-0.5,0.05); return

	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: mouse_dragging=true; mouse_last=event.position; auto_orbit=false
			else: mouse_dragging=false
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP: cam_radius=maxf(cam_radius-0.5,2.0); auto_orbit=false
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: cam_radius=minf(cam_radius+0.5,18.0); auto_orbit=false
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: auto_orbit=not auto_orbit
	elif event is InputEventMouseMotion and mouse_dragging:
		var dm=event.position-mouse_last; mouse_last=event.position
		cam_theta-=dm.x*0.005; cam_phi+=dm.y*0.005; cam_phi=clamp(cam_phi,-1.2,1.2)


# ═══════════════════════════════════════════
# FILE LOADERS (via dialog)
# ═══════════════════════════════════════════
func _try_load_image():
	var fd = FileDialog.new(); fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.png,*.jpg,*.jpeg,*.bmp","Images")
	fd.file_selected.connect(_on_image_selected); add_child(fd); fd.popup_centered(Vector2(600,400))


func _on_image_selected(path: String):
	load_image_cloud(path)
	(get_node(path) as FileDialog).queue_free()


func _try_load_video():
	var fd = FileDialog.new(); fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.mp4,*.ogv,*.webm","Videos")
	fd.file_selected.connect(_on_video_selected); add_child(fd); fd.popup_centered(Vector2(600,400))


func _on_video_selected(path: String):
	load_video(path)
	(get_node(path) as FileDialog).queue_free()


func _try_load_skybox():
	var fd = FileDialog.new(); fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.png,*.jpg,*.jpeg","Skybox Images")
	fd.file_selected.connect(_on_skybox_selected); add_child(fd); fd.popup_centered(Vector2(600,400))


func _on_skybox_selected(path: String):
	load_skybox(path)
	(get_node(path) as FileDialog).queue_free()
