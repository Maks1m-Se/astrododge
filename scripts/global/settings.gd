# res://scripts/global/settings.gd
extends Node

const CFG_PATH := "user://settings.cfg"
const SECT_GAME := "game"

var selected_ship_path: String = "res://data/ships/scout.tres"

func _ready() -> void:
	load_settings()

func set_selected_ship_path(path: String) -> void:
	if selected_ship_path == path:
		return
	selected_ship_path = path
	save_settings()

func get_selected_ship_path() -> String:
	return selected_ship_path

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		selected_ship_path = String(cfg.get_value(SECT_GAME, "ship_config", selected_ship_path))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECT_GAME, "ship_config", selected_ship_path)
	cfg.save(CFG_PATH)
