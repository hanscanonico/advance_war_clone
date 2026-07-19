class_name CommanderState
extends RefCounted
## One team's commander for the match in progress: who they are, how much charge
## the meter holds, and whether their Command Power is currently running.
##
## The split matters: CommanderType is shared immutable data loaded from a
## .tres, so it can never hold anything about a particular match. Everything
## that changes during play lives here, one instance per team.

var type: CommanderType
## Charge points banked so far, never above `type.power_cost`.
var charge: int = 0
var power_active: bool = false


static func create(p_type: CommanderType) -> CommanderState:
	var co_state := CommanderState.new()
	co_state.type = p_type if p_type != null else CommanderType.neutral()
	return co_state


## 0.0 - 1.0, for the HUD meter. A commander with no power never fills.
func charge_ratio() -> float:
	if not type.has_power():
		return 0.0
	return clampf(float(charge) / float(type.power_cost), 0.0, 1.0)


## True when the power can be fired: the meter is full and it is not already up.
func is_ready() -> bool:
	return type.has_power() and charge >= type.power_cost and not power_active
