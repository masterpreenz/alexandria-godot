class_name GameClock
extends Node
## The world's time (from Unity's GameClock): the hour of the day, the day count, the season (a few days each, round
## the year) and the weather, which can change every few hours and depends on the season (storms in the warm seasons,
## snow only in winter). Lighting, weather effects and the HUD read it.
##
## The weather is rolled with the same odds per season as Unity, from a hash of the stretch of hours (Unity used .NET's
## System.Random, which can't be reproduced here), so a given day's weather differs from the Unity build's.

signal weather_changed(weather: int)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW }
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const WEATHER_NAMES := ["Clear", "Cloudy", "Rain", "Storm", "Snow"]

var seconds_per_day := 720.0
var days_per_season := 7
var start_season := Season.SPRING
var weather_hours := 6.0
var weather_seed := 1234
## How many times faster than usual the day passes (faster while sleeping).
var speed := 1.0
## Game hours since midnight of day 1.
var hours := 8.0
## Weather picked by hand (it stays until changed), or -1 to follow the season.
var forced := -1

var _rolled := Weather.CLEAR
var _slot := -1


func day() -> int:
	return floori(hours / 24.0) + 1


func hour() -> float:
	return fmod(hours, 24.0)


func season() -> int:
	@warning_ignore("integer_division")
	return (start_season + (day() - 1) / maxi(1, days_per_season)) % 4


func day_of_season() -> int:
	return (day() - 1) % maxi(1, days_per_season) + 1


## The weather now: the one picked by hand, else the season's roll.
func weather() -> int:
	return forced if forced >= 0 else _rolled


## How light it is outside: 0 at night, 1 in full day, in between at dawn and dusk.
func daylight() -> float:
	var h := hour()
	if h < 5.0 or h >= 20.0: return 0.0
	if h < 7.0: return smoothstep(0.0, 1.0, (h - 5.0) / 2.0)
	if h < 18.0: return 1.0
	return smoothstep(1.0, 0.0, (h - 18.0) / 2.0)


## The time as "8:30 AM".
func time_text() -> String:
	var total := floori(hour() * 60.0)
	@warning_ignore("integer_division")
	var h := total / 60
	var h12 := 12 if h % 12 == 0 else h % 12
	return "%d:%02d %s" % [h12, total % 60, "AM" if h < 12 else "PM"]


## Jumps the clock to [param h] on the current day.
func set_hour(h: float) -> void:
	hours = (day() - 1) * 24.0 + fposmod(h, 24.0)
	_update_weather()


## Holds the weather at [param w]; -1 lets the season pick it again.
func set_weather(w: int) -> void:
	var before := weather()
	forced = w
	if weather() != before:
		weather_changed.emit(weather())


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"game_clock.process", __t)


func _process_timed(delta: float) -> void:
	hours += delta * speed * 24.0 / maxf(1.0, seconds_per_day)
	_update_weather()


func _update_weather() -> void:
	var slot := floori(hours / maxf(0.5, weather_hours))
	if slot == _slot:
		return
	_slot = slot
	var before := weather()
	@warning_ignore("int_as_enum_without_cast")
	_rolled = _roll(slot)
	if weather() != before:
		weather_changed.emit(weather())


# The weather for one stretch of hours, from how likely each kind is this season.
func _roll(slot: int) -> int:
	var h := hash(weather_seed * 7919 + slot)
	var r := float(h & 0xFFFFFF) / float(0x1000000)
	match season():
		Season.SPRING: return Weather.CLEAR if r < 0.5 else Weather.CLOUDY if r < 0.75 else Weather.RAIN if r < 0.92 else Weather.STORM
		Season.SUMMER: return Weather.CLEAR if r < 0.65 else Weather.CLOUDY if r < 0.85 else Weather.RAIN if r < 0.93 else Weather.STORM
		Season.AUTUMN: return Weather.CLEAR if r < 0.35 else Weather.CLOUDY if r < 0.65 else Weather.RAIN if r < 0.88 else Weather.STORM
	return Weather.CLEAR if r < 0.35 else Weather.CLOUDY if r < 0.6 else Weather.SNOW


## The saved clock (Unity's world.clock section: hours, forcedWeather).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	hours = maxf(0.0, float(d.get("hours", hours)))
	forced = int(d.get("forcedWeather", -1))
	_slot = -1
	_update_weather()


func to_json() -> String:
	return JSON.stringify({"hours": hours, "forcedWeather": forced})
