local DEFAULT_PLAYER_COLOR = Vector(62 / 255, 88 / 255, 106 / 255)

---Define a set of proxies so that the reset function doesn't erroneously call
---if we already have one of these proxies
---@type Set<MaterialProxy>
local cloakProxies = {
	spy_invis = true,
	invis = true,
	building_invis = true,
	weapon_invis = true,
}

---@type Set<MaterialProxy>
local glowProxies = {
	YellowLevel = true,
	ModelGlowColor = true,
}

---@type DataResetter
local function glowReset(ply, ent, data)
	local old = ent.ProxyentCritGlow
	if IsValid(old) then
		old:Remove()
		ent.ProxyentCritGlow = nil
	end
	duplicator.ClearEntityModifier(ent, "MatproxyTF2CritGlow")
end

---@type ProxyTransformer
local cloakFuncs = {
	entity = {
		name = "ProxyentCloakEffect",
		varMap = {
			color = "CloakTintVector",
			matproxy_tf2cloakeffect_factor = "CloakFactor",
			matproxy_tf2cloakeffect_refractamount = "CloakRefractAmount",
			matproxy_tf2cloakeffect_disableshadow = "CloakDisablesShadow",
			matproxy_tf2cloakeffect_anim = "CloakAnim",
			matproxy_tf2cloakeffect_anim_toggle = "CloakAnimToggle",
			matproxy_tf2cloakeffect_anim_timein = "CloakAnimTimeIn",
			matproxy_tf2cloakeffect_anim_timeout = "CloakAnimTimeOut",
		},
	},
	apply = GiveMatproxyTF2CloakEffect, ---@diagnostic disable-line
	transform = function(proxy)
		return {
			TintR = proxy.color.r,
			TintG = proxy.color.g,
			TintB = proxy.color.b,
			Anim = proxy.data.matproxy_tf2cloakeffect_anim,
			Anim_Toggle = proxy.data.matproxy_tf2cloakeffect_anim_toggle,
			Anim_StartOn = proxy.data.matproxy_tf2cloakeffect_anim_starton,
			Anim_TimeIn = proxy.data.matproxy_tf2cloakeffect_anim_timein,
			Anim_TimeOut = proxy.data.matproxy_tf2cloakeffect_anim_timeout,
			Factor = proxy.data.matproxy_tf2cloakeffect_factor,
			RefractAmount = proxy.data.matproxy_tf2cloakeffect_refractamount,
			DisableShadow = proxy.data.matproxy_tf2cloakeffect_disableshadow,
		}
	end,
	reset = function(ply, ent, data)
		local old = ent.ProxyentCloakEffect
		if IsValid(old) then
			old:Remove()
			ent.ProxyentCloakEffect = nil
		end
		duplicator.ClearEntityModifier(ent, "MatproxyTF2CloakEffect")
	end,
}

local proxyTransformers = {
	["ItemTintColor"] = {
		entity = {
			name = "ProxyentPaintColor",
			varMap = {
				color = "Color",
				matproxy_tf2itempaint_override = "PaintOverride",
			},
		},
		apply = GiveMatproxyTF2ItemPaint, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
				PaintOverride = proxy.data.matproxy_tf2itempaint_override,
			}
		end,
		reset = function(ply, ent, data)
			local old = ent.ProxyentPaintColor
			if IsValid(old) then
				old:Remove()
				ent.ProxyentPaintColor = nil
			end
			duplicator.ClearEntityModifier(ent, "MatproxyTF2ItemPaint")
		end,
	},
	["YellowLevel"] = {
		entity = {
			name = "ProxyentCritGlow",
			varMap = {
				color = "Color",
				matproxy_tf2critglow_sparksr = "SparksRed",
				matproxy_tf2critglow_sparksb = "SparksBlu",
				matproxy_tf2critglow_sparksc = "SparksColorable",
				matproxy_tf2critglow_sparksj = "SparksJarate",
				matproxy_tf2critglow_sparksjc = "SparksJarateColorable",
			},
		},
		apply = GiveMatproxyTF2CritGlow, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				JarateSparks = proxy.data.matproxy_tf2critglow_sparksj,
				JarateColorable = proxy.data.matproxy_tf2critglow_sparksjc,
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
			}
		end,
		reset = glowReset,
	},
	["spy_invis"] = cloakFuncs,
	["invis"] = cloakFuncs,
	["weapon_invis"] = cloakFuncs,
	["building_invis"] = cloakFuncs,
	["ModelGlowColor"] = {
		entity = {
			name = "ProxyentCritGlow",
			varMap = {
				color = "Color",
				matproxy_tf2critglow_sparksr = "SparksRed",
				matproxy_tf2critglow_sparksb = "SparksBlu",
				matproxy_tf2critglow_sparksc = "SparksColorable",
				matproxy_tf2critglow_sparksj = "SparksJarate",
				matproxy_tf2critglow_sparksjc = "SparksJarateColorable",
			},
		},
		apply = GiveMatproxyTF2CritGlow, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				RedSparks = proxy.data.matproxy_tf2critglow_sparksr,
				BluSparks = proxy.data.matproxy_tf2critglow_sparksb,
				ColorableSparks = proxy.data.matproxy_tf2critglow_sparksc or 0,
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
			}
		end,
		reset = glowReset,
	},
	["PlayerColor"] = {
		-- FIXME: Support for Stik's tools or Ragdoll Colorizer
		apply = function(ply, ent, data)
			---@diagnostic disable-next-line
			if isfunction(RagdollColorEntityTable) then
				---@diagnostic disable-next-line
				local tbl = RagdollColorEntityTable()

				local vector = { data.r / 255, data.g / 255, data.b / 255 }
				table.insert(tbl, ent:EntIndex(), ent)
				ent:SetNWVector("stikragdollcolorer", vector)

				local count = table.Count(tbl)

				net.Start("ragdolltblclient")
				net.WriteBit(false)
				net.WriteUInt(count, 13)
				for k, v in pairs(tbl) do
					net.WriteEntity(v)
				end
				net.Broadcast()
			else
				if util.NetworkStringToID("SendToRagdollClient") ~= 0 then
					net.Start("SendToRagdollClient")
					net.WriteTable({ ent, data })
					net.Send(ply)
				end

				ent.GetPlayerColor = function()
					return Vector(data.r / 255, data.g / 255, data.b / 255)
				end
			end
		end,
		transform = function(proxy)
			return proxy.color
		end,
		reset = function(ply, ent, data)
			---@diagnostic disable-next-line
			if isfunction(RagdollColorEntityTable) then
				---@diagnostic disable-next-line
				local tbl = RagdollColorEntityTable()

				ent:SetNWVector("stikragdollcolorer", DEFAULT_PLAYER_COLOR)
				ent.GetPlayerColor = nil
				duplicator.ClearEntityModifier(ent, "stikRagdollColor")
				tbl[ent:EntIndex()] = NULL
			else
				if SERVER then
					net.Start("SendToRagdollClient")
					net.WriteTable({ ent, DEFAULT_PLAYER_COLOR })
					net.Send(ply)
				end

				Entity.GetPlayerColor = function()
					return DEFAULT_PLAYER_COLOR
				end
			end
		end,
	},
}

return {
	proxyTransformers = proxyTransformers,
	glowProxies = glowProxies,
	cloakProxies = cloakProxies,
	glowReset = glowReset,
	cloakFuncs = cloakFuncs,
	DEFAULT_PLAYER_COLOR = DEFAULT_PLAYER_COLOR,
}
