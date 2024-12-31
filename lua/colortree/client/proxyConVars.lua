local cloakConVars = {
	{ "matproxy_tf2cloakeffect_anim", "DCheckBoxLabel" },
	{ "matproxy_tf2cloakeffect_anim_starton", "DCheckBoxLabel" },
	{ "matproxy_tf2cloakeffect_anim_timein", "DNumSlider" },
	{ "matproxy_tf2cloakeffect_anim_timeout", "DNumSlider" },
	{ "matproxy_tf2cloakeffect_anim_toggle", "DCheckBoxLabel" },
	{ "matproxy_tf2cloakeffect_disableshadow", "DCheckBoxLabel" },
	{ "matproxy_tf2cloakeffect_factor", "DNumSlider" },
	{ "matproxy_tf2cloakeffect_refractamount", "DNumSlider" },
}

---@type ProxyConVarMap
local proxyConVarMap = {
	PlayerColor = {},
	ItemTintColor = {
		{ "matproxy_tf2itempaint_override", "DCheckBoxLabel" },
	},
	ModelGlowColor = {
		{ "matproxy_tf2critglow_sparksr", "DCheckBoxLabel" },
		{ "matproxy_tf2critglow_sparksb", "DCheckBoxLabel" },
		{ "matproxy_tf2critglow_sparksc", "DCheckBoxLabel" },
	},
	YellowLevel = {
		{ "matproxy_tf2critglow_sparksj", "DCheckBoxLabel" },
		{ "matproxy_tf2critglow_sparksjc", "DCheckBoxLabel" },
	},
	spy_invis = cloakConVars,
	invis = cloakConVars,
	weapon_invis = cloakConVars,
	building_invis = cloakConVars,
}

return proxyConVarMap
