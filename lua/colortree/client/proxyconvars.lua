local cloakConVars = {
	{ "matproxy_tf2cloakeffect_anim", "DCheckBoxLabel", "Is Animated?" },
	{ "matproxy_tf2cloakeffect_anim_starton", "DCheckBoxLabel", "Start on?" },
	{ "matproxy_tf2cloakeffect_anim_timein", "DNumSlider", "Cloak fade time" },
	{ "matproxy_tf2cloakeffect_anim_timeout", "DNumSlider", "Decloak fade time" },
	{ "matproxy_tf2cloakeffect_anim_toggle", "DCheckBoxLabel", "Toggle" },
	{ "matproxy_tf2cloakeffect_disableshadow", "DCheckBoxLabel", "Cloak disables shadow" },
	{ "matproxy_tf2cloakeffect_factor", "DNumSlider", "Cloak factor" },
	{ "matproxy_tf2cloakeffect_refractamount", "DNumSlider", "Refract amount" },
}

---@type ProxyConVarMap
local proxyConVarMap = {
	PlayerColor = {},
	ItemTintColor = {
		{ "matproxy_tf2itempaint_override", "DNumSlider", "Paint Override" },
	},
	ModelGlowColor = {
		{ "matproxy_tf2critglow_sparksr", "DCheckBoxLabel", "RED Sparks" },
		{ "matproxy_tf2critglow_sparksb", "DCheckBoxLabel", "BLU Sparks" },
		{ "matproxy_tf2critglow_sparksc", "DCheckBoxLabel", "Colorable Sparks" },
	},
	YellowLevel = {
		{ "matproxy_tf2critglow_sparksj", "DCheckBoxLabel", "Jarate Drips" },
		{ "matproxy_tf2critglow_sparksjc", "DCheckBoxLabel", "Colorable Drips" },
	},
	spy_invis = cloakConVars,
	invis = cloakConVars,
	weapon_invis = cloakConVars,
	building_invis = cloakConVars,
}

return proxyConVarMap
