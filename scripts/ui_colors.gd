extends RefCounted

const BG_DARK := Color("0a1f23")
const BG_PANEL := Color("092528")
const PANEL := BG_PANEL
const TEAL := Color("1c4f4e")
const TEAL_MID := Color("348270")
const MINT := Color("96f2d8")
const WHITE := Color("e6fff8")
const TEXT_PRIMARY := Color("e6fff8")
const TEXT_SECONDARY := Color("7fe8d2")
const ACCENT_TEAL := Color("3cffd0")
const TEAM_A_COLOR := Color("4db8ff")
const TEAM_B_COLOR := Color("8cff5a")
const TEAM_C_COLOR := Color("ffbe5c")
const TEAM_D_COLOR := Color("e88cff")
const TEAM_E_COLOR := Color("ff6f91")
const DANGER := Color("ff4d4d")
const WARNING := Color("ffc24d")
const SUCCESS := Color("5cff9d")
const CYAN := Color("50c8ff")
const GREEN := SUCCESS
const ALERT := DANGER
const BUILDING_DIM := Color(0.7, 0.7, 0.7)
const GLOBAL_BRIGHTNESS := 1.0
const MAP_RECESS := BUILDING_DIM
const JUICE_ENABLED := true


static func team_color(label: String) -> Color:
	match label:
		"A":
			return TEAM_A_COLOR
		"B":
			return TEAM_B_COLOR
		"C":
			return TEAM_C_COLOR
		"D":
			return TEAM_D_COLOR
		"E":
			return TEAM_E_COLOR
	return TEAM_A_COLOR
