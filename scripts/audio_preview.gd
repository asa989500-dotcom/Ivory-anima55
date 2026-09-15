class_name AudioPreview
extends Node
## The scene's sounds, heard while the timeline plays.
##
## Deliberately simple, and simple in a particular direction: it does not try
## to be the export. The export is sample-exact and takes as long as it takes;
## this has to keep up with a playhead a person is dragging, on a phone, while
## eight layers are being composited. So it hands each clip to Godot's own
## audio server with a start offset and then leaves it alone — the platform's
## mixer is far better at this than anything written on top of it.
##
## What follows from that: a clip is started when the playhead reaches it and
## stopped when playback stops or the head is moved. Scrubbing does not play
## sound, because scrubbing at a hundred frames a second through a soundtrack
## is a noise nobody wants and every app that has tried it has taken it out.
##
## Formats Godot cannot decode on its own — M4A, FLAC, WMA and the rest — are
## silent here until they have been exported once, at which point the prepared
## copy exists and is used. That is an honest limit, said plainly in the
## panel, and it costs nothing at export.

## As many sounds as may be heard at one moment.
##
## Above this, the oldest is dropped. Not a musical judgement — a phone's
## audio server has a finite number of voices, and forty at once is already
## past the point where any of them is distinguishable.
const VOICES: int = 24

var track: AudioTrack = null
var clip: Anim.Clip = null

var _players: Array = []
var _live: Dictionary = {}

func _ready() -> void:
	for i in VOICES:
		var one: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(one)
		_players.append(one)

## Starts everything that should already be sounding at this frame, part-way
## through where that is what the frame means.
func begin(at_frame: int) -> void:
	silence()
	if track == null or clip == null:
		return
	var now: float = clip.time_of(at_frame)
	for c in track.live_clips():
		var one: AudioTrack.Clip = c as AudioTrack.Clip
		var starts: float = clip.time_of(one.start_frame)
		var into: float = now - starts
		if into < -0.001:
			continue
		if one.seconds > 0.0 and into >= one.seconds - one.skip:
			continue
		_start(one, maxf(into, 0.0))

## Called as the playhead moves, so a sound placed further along the scene
## comes in when it is reached rather than only when play is pressed.
func step(at_frame: int) -> void:
	if track == null or clip == null:
		return
	var now: float = clip.time_of(at_frame)
	for c in track.live_clips():
		var one: AudioTrack.Clip = c as AudioTrack.Clip
		if _live.has(one):
			continue
		var starts: float = clip.time_of(one.start_frame)
		# A small window rather than an exact moment: a rendered frame is a
		# fortieth of a second wide and the start of a clip lands inside one
		# of them, not on the join between two.
		if now + 0.05 < starts or now - starts > 0.25:
			continue
		_start(one, maxf(now - starts, 0.0))

func silence() -> void:
	for p in _players:
		(p as AudioStreamPlayer).stop()
	_live.clear()

func _start(one: AudioTrack.Clip, into: float) -> void:
	var stream: AudioStream = AudioBank.make_stream(one.path)
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_player()
	if player == null:
		return
	player.stream = stream
	# Decibels, because that is what the audio server speaks. A gain of zero
	# would be minus infinity, which is why it is guarded rather than
	# converted.
	player.volume_db = -80.0 if one.gain <= 0.001 \
		else linear_to_db(clampf(one.gain, 0.001, 4.0))
	player.play(one.skip + into)
	_live[one] = player

func _free_player() -> AudioStreamPlayer:
	for p in _players:
		var one: AudioStreamPlayer = p as AudioStreamPlayer
		if not one.playing:
			return one
	# Everything is busy. The oldest is taken rather than the newest refused:
	# a sound that has been going for a while is the one already understood.
	var oldest: AudioStreamPlayer = _players[0] as AudioStreamPlayer
	oldest.stop()
	return oldest
