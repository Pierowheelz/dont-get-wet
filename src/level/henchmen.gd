extends Node3D
## The level's `henchmen`: men in the walker's own suit, each waiting under cover at his x with his
## umbrella furled like any doorman, facing back down the street. When the walker comes within RANGE
## of one, in the frame, he opens the umbrella and fires telegraphed jets (WaterJet) on a timer: the gaps cycle
## through INTERVALS, each nudged by up to JITTER, counted from the moment the last jet has landed.
## Between shots he holds the canopy overhead, so the walker's shot reaches his chest; while he aims
## it is brought down at the walker and stops the shot. Once the walker is past him he turns round
## and keeps firing from behind while the walker is still in range and on screen.
## A jet that lands in full wets the walker HIT. Each man is an NpcBody: two clean hits soak him, and
## he gives up as the walker does.
## `dealt_with(i)` fires once per man, when he is soaked or the walker reaches him.
## A checkpoint resume leaves out every man more than RANGE behind the restore point.

signal dealt_with(index: int)

enum Phase { WAIT, OPEN, FIRE, DONE }

const INTERVALS := [2.4, 3.1, 2.7, 3.4]
const JITTER := 0.2
const RANGE := 7.5          # he opens up on the walker within this, ahead or behind
const LANE_Z := 0.75        # back by the shopfronts, under the canopy
const OPEN_S := 0.9         # the umbrella goes up before the first glint
const FIRST_SHOT := 0.5     # after it is open
const TURN_RATE := 5.0      # rad/s
const PASS_M := 0.35        # the walker is past him this far beyond his x
const REACH_M := 1.0        # he is dealt with once the walker is this close
const HIT := 8.0            # wetness of a jet that lands in full (the walker's wet_max is 50)

## One man: his body, where he waits and how far through his routine he is.
class Man:
	var index := 0
	var x := 0.0
	var body: NpcBody
	var phase := Phase.WAIT
	var facing := -1.0      # -1 toward the walker coming up the street, +1 after he has passed
	var open := 0.0
	var aim := 0.0
	var shot_t := 0.0
	var next := 0           # index into INTERVALS
	var jet: WaterJet
	var dealt := false

	func incoming() -> bool:
		return jet != null and is_instance_valid(jet) and jet.phase != WaterJet.Phase.SPENT

	func up() -> bool:
		return body != null and is_instance_valid(body) and body.wettable() and phase != Phase.DONE


var level: Node
var men: Array[Man] = []
var _hinted := false


func _ready() -> void:
	var xs: Array = level.data.get("henchmen", []).map(func(h: Dictionary) -> float: return float(h["x"]))
	xs.sort()
	var start_x: float = level.player.position.x
	for i in xs.size():
		var m := Man.new()
		m.index = i
		m.x = xs[i]
		m.next = i % INTERVALS.size()
		men.append(m)
		if m.x < start_x - RANGE:
			m.phase = Phase.DONE
			m.dealt = true
			continue
		m.body = NpcBody.new()
		m.body.level = level
		add_child(m.body)
		m.body.position = Vector3(m.x, level.ground_y(m.x), LANE_Z)
		m.body.rotation.y = PI
		m.body.soaked.connect(_on_soaked.bind(m))
		_pose(m, 0.0)


func _on_soaked(m: Man) -> void:
	_drop_jet(m)
	m.phase = Phase.DONE
	_deal(m)


func _deal(m: Man) -> void:
	if not m.dealt:
		m.dealt = true
		dealt_with.emit(m.index)


func _drop_jet(m: Man) -> void:
	if m.jet and is_instance_valid(m.jet) and m.jet.phase == WaterJet.Phase.GLINT:
		m.jet.queue_free()
	m.jet = null


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null or level.camera == null:
		return
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	for m in men:
		if not m.up():
			continue
		if not m.dealt and p.position.x > m.x - REACH_M:
			_deal(m)
		var want := 1.0 if p.position.x > m.x + PASS_M else -1.0
		if want != m.facing:
			m.facing = want
			_drop_jet(m)          # he was aiming the other way
			m.shot_t = maxf(m.shot_t, FIRST_SHOT)
		var in_range := playing and absf(p.position.x - m.x) <= RANGE and _on_screen(m)
		match m.phase:
			Phase.WAIT:
				if in_range:
					m.phase = Phase.OPEN
					if not _hinted:
						_hinted = true
						level.hint_once("henchman", "He's looking for a face. Soak him ({fire}), or hide behind the umbrella ({tilt_forward}) and walk past.", 5.0)
			Phase.OPEN:
				m.open = move_toward(m.open, 1.0, delta / OPEN_S)
				if m.open >= 1.0:
					m.phase = Phase.FIRE
					m.shot_t = FIRST_SHOT
			Phase.FIRE:
				if not playing:
					_drop_jet(m)
				elif not m.incoming() and in_range and absf(_yaw(m) - m.body.rotation.y) < 0.2:
					m.shot_t -= delta
					if m.shot_t <= 0.0:
						_fire(m)
		_pose(m, delta)


func _fire(m: Man) -> void:
	m.shot_t = INTERVALS[m.next] + randf_range(-JITTER, JITTER)
	m.next = (m.next + 1) % INTERVALS.size()
	var body := m.body
	m.jet = WaterJet.fire(level, func() -> Transform3D:
		var t := body.umbrella.global_transform
		return Transform3D(t.basis, t * Vector3(0.0, Umbrella.SHAFT_LEN + 0.09, 0.0)), HIT)
	m.jet.shooter = body


func _on_screen(m: Man) -> bool:
	return level.in_frame(m.x, LANE_Z)


func _yaw(m: Man) -> float:
	# Squared up to the walker's lane, so the canopy he brings down faces the shot that comes at it.
	var p: Node3D = level.player
	var dx := maxf(absf(p.position.x - m.body.position.x), 1.0)
	var turn := clampf(atan2(p.position.z - m.body.position.z, dx), -0.45, 0.45)
	return PI + turn if m.facing < 0.0 else -turn


## Furled at his side while he waits; open overhead between shots; brought down at the walker to aim.
func _pose(m: Man, delta: float) -> void:
	var b := m.body
	b.rotation.y = move_toward(b.rotation.y, _yaw(m), TURN_RATE * delta)
	m.aim = move_toward(m.aim, WaterJet.AIM_TILT if m.incoming() else 0.0, delta * 4.0)
	var raise := lerpf(m.open, WaterJet.AIM_RAISE, m.aim / WaterJet.AIM_TILT)
	b.visual.call("set_motion", 0.0, 0.0)
	b.visual.call("set_stopped", false)
	b.visual.call("set_umbrella_pose", raise, m.aim, 0.0)
	b.visual.call("set_umbrella_open", m.open)
	b.umbrella.set_state(m.open, Game.umbrella_radius(0), 0.0)


# --- for the bots -------------------------------------------------------------------------------

## The men who can still fire at the walker.
func _live() -> Array:
	return men.filter(func(m: Man) -> bool: return m.up() and m.phase in [Phase.OPEN, Phase.FIRE])


## A jet is glinting or in the air.
func incoming() -> bool:
	return men.any(func(m: Man) -> bool: return m.up() and m.incoming())


## The side (+1 ahead, -1 behind) a jet is glinting or coming in from, 0 if none.
func brace_side() -> float:
	var p: Player = level.player
	for m in men:
		if m.up() and m.incoming():
			return signf(m.x - p.position.x)
	return 0.0


## Someone is shooting at the walker now.
func armed() -> bool:
	var p: Player = level.player
	return _live().any(func(m: Man) -> bool: return absf(p.position.x - m.x) <= RANGE)


## Seconds until the next glint could start (INF when nobody is on him).
func next_glint_in() -> float:
	var p: Player = level.player
	var best := INF
	for m in men:
		if not m.up() or absf(p.position.x - m.x) > RANGE + 1.5:
			continue
		if m.incoming():
			return 0.0
		match m.phase:
			Phase.WAIT:
				best = minf(best, OPEN_S + FIRST_SHOT)
			Phase.OPEN:
				best = minf(best, (1.0 - m.open) * OPEN_S + FIRST_SHOT)
			Phase.FIRE:
				best = minf(best, maxf(m.shot_t, 0.0))
	return best
