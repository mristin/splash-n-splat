class_name SoundBank
extends Node

## Synthesize the game's sounds at startup, so that we need no audio files: the
## throw, the soft splat, the bear's boing, the hit, the pop, the jingles and
## the drone of the little plane on the travel map.

enum Sound { THROW, SPLAT, BOING, PLAYER_HIT, POP, WIN, LOSE, START, PLANE, MEOW, POWER_UP }

const _RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _random := RandomNumberGenerator.new()
var _low := 0.0


func _ready() -> void:
    _random.seed = 7
    _streams[Sound.THROW] = _make(
        0.22,
        func(t: float) -> float:
            return _noise() * _envelope(t, 0.22, 0.02) * 0.35 * (0.4 + t / 0.22)
    )
    _streams[Sound.SPLAT] = _make(
        0.28, func(t: float) -> float: return _low_noise(0.25) * _envelope(t, 0.28, 0.005) * 0.9
    )
    _streams[Sound.PLAYER_HIT] = _make(
        0.45,
        func(t: float) -> float:
            return (
                (_low_noise(0.12) * 0.8 + sin(TAU * (90 - 60 * t) * t) * 0.5)
                * _envelope(t, 0.45, 0.005)
            )
    )
    _streams[Sound.BOING] = _make(
        0.4,
        func(t: float) -> float:
            return (
                sin(TAU * (520 * t - 300 * t * t + 15 * sin(t * 60)))
                * _envelope(t, 0.4, 0.01)
                * 0.45
            )
    )
    _streams[Sound.POP] = _make(
        0.12,
        func(t: float) -> float:
            return (sin(TAU * 900 * t) * 0.4 + _noise() * 0.3) * _envelope(t, 0.12, 0.002)
    )
    _streams[Sound.WIN] = _melody([523.25, 659.25, 783.99, 1046.5], 0.16)
    _streams[Sound.LOSE] = _melody([392.0, 349.23, 311.13, 261.63], 0.2)
    _streams[Sound.START] = _melody([659.25, 987.77], 0.1)
    _streams[Sound.POWER_UP] = _melody([523.25, 783.99, 1046.5, 1567.98], 0.07)
    # NOTE (mristin):
    # A sad, falling meow with a wobble: the hit kitten cries.
    _streams[Sound.MEOW] = _make(
        0.7,
        func(t: float) -> float:
            var phase := TAU * (900.0 * t - 320.0 * t * t) + 0.6 * sin(TAU * 7.0 * t)
            return (
                (sin(phase) * 0.5 + sin(2.0 * phase) * 0.2 + sin(3.0 * phase) * 0.08)
                * _envelope(t, 0.7, 0.06)
                * 0.5
            )
    )
    # NOTE (mristin):
    # A soft propeller drone: a low hum, chopped by the blades, which rises a
    # little at the take-off and fades out at the landing.
    _streams[Sound.PLANE] = _make(
        6.0,
        func(t: float) -> float:
            var pitch := 85.0 + 25.0 * sin(clampf(t / 6.0, 0.0, 1.0) * PI)
            var hum := sin(TAU * pitch * t) * 0.6 + sin(TAU * pitch * 2.0 * t) * 0.25
            var chop := 0.6 + 0.4 * sin(TAU * 22.0 * t)
            return (
                (hum * chop + _low_noise(0.3) * 0.15)
                * clampf(minf(t / 0.8, (6.0 - t) / 1.5), 0.0, 1.0)
                * 0.4
            )
    )

    for i in range(8):
        var player := AudioStreamPlayer.new()
        add_child(player)
        _players.append(player)


## Stop the sound wherever it plays.
func stop(sound: Sound) -> void:
    for player in _players:
        if player.playing and player.stream == _streams[sound]:
            player.stop()


func play(sound: Sound, volume_db: float = 0.0) -> void:
    var player := _players[_next]
    _next = (_next + 1) % _players.size()
    player.stream = _streams[sound]
    player.volume_db = volume_db
    player.pitch_scale = 0.95 + _random.randf() * 0.1
    player.play()


func _noise() -> float:
    return _random.randf() * 2.0 - 1.0


## Low-passed noise; the lower the factor, the duller the sound.
func _low_noise(factor: float) -> float:
    _low += factor * (_noise() - _low)
    return _low * 2.5


static func _envelope(t: float, length: float, attack: float) -> float:
    if t < attack:
        return t / attack
    var x := maxf(0.0, 1.0 - (t - attack) / (length - attack))
    return x * x


func _melody(notes: Array, note_seconds: float) -> AudioStreamWAV:
    return _make(
        notes.size() * note_seconds + 0.2,
        func(t: float) -> float:
            var index := mini(notes.size() - 1, int(t / note_seconds))
            var local := t - index * note_seconds
            var tail := 0.2 if index == notes.size() - 1 else 0.0
            var f: float = notes[index]
            return (
                (sin(TAU * f * t) * 0.6 + sin(TAU * 2 * f * t) * 0.15)
                * _envelope(local, note_seconds + tail, 0.01)
                * 0.4
            )
    )


func _make(seconds: float, sample: Callable) -> AudioStreamWAV:
    var count := int(seconds * _RATE)
    var data := PackedByteArray()
    data.resize(count * 2)
    for i in range(count):
        var value := clampf(sample.call(float(i) / _RATE), -1.0, 1.0)
        data.encode_s16(2 * i, int(value * 32767 * 0.8))

    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = _RATE
    stream.stereo = false
    stream.data = data
    return stream
