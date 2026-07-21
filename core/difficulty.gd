class_name Difficulty
extends Resource
## One difficulty tier: an id, the name the menu shows, and the AIProfile the
## computer plays with. Difficulty pulls exactly one lever — which profile the AI
## weighs its moves against — so a tier *is* its profile plus a label. The player
## plays the same rules, economy, vision and dice at every tier; only the
## opponent's judgement changes.
##
## Data, not behaviour, like the commander and unit resources: the three tiers
## are .tres files under data/difficulty/, and tuning one is editing its profile.
## A plain Resource with no Node reference, so tests and the headless tools build
## it as freely as the rest of the sim.

const DEFAULT_ID := &"normal"

@export var id: StringName = DEFAULT_ID
@export var display_name: String = "Normal"
## The AI's judgement at this tier. Easy and Difficult ship their own profile;
## Normal points at data/ai/default.tres, so Normal is the shipped AI unchanged.
@export var ai_profile: AIProfile


## Never null: a tier whose profile file is missing falls back to the shipped
## default profile rather than taking the AI out — the same defensive default
## AIController itself reaches for when handed nothing.
func profile() -> AIProfile:
	return ai_profile if ai_profile != null else AIProfile.load_default()
