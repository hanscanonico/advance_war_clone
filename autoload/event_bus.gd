extends Node
## Global signal bus for presentation-level events.
##
## The simulation core in res://core/ must never reference this (or any Node).
## Scenes emit and subscribe here so UI widgets don't need direct references
## to the battle scene.

signal cursor_moved(cell: Vector2i)
signal unit_moved(unit: Unit)
signal unit_built(unit: Unit)
signal property_captured(cell: Vector2i, team: int)
signal turn_started(team: int, day: int)
signal power_activated(team: int, commander: CommanderType)
