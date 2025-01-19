TOOL.Category = "Render"
TOOL.Name = "#tool.colortree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["proxy"] = ""
TOOL.ClientConVar["lock"] = 0
TOOL.ClientConVar["propagate"] = 0

local CHANGE_BITS = 7
local TIME_PRECISION = 10

---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")
---@module "colortree.shared.proxytransformers"
local pt = include("colortree/shared/proxytransformers.lua")

local cloakProxies, glowProxies, proxyTransformers = pt.cloakProxies, pt.glowProxies, pt.proxyTransformers

local decodeData, isAdvancedColorsInstalled, getAncestor =
	helpers.decodeData, helpers.isAdvancedColorsInstalled, helpers.getAncestor

do -- Keep track of the last time the (sub)colors of an entity or its children has changed
	---@class Colorable
	local meta = FindMetaTable("Entity")
	if meta.colortree_oldSetColor == nil then
		meta.colortree_oldSetColor = meta.SetColor
	end

	---Propagate the changed color event to the ancestral entity
	---@param entity Entity
	local function updateColor(entity)
		net.Start("colortree_update", true)
		net.WriteEntity(entity)
		net.WriteUInt(CurTime() * TIME_PRECISION, CHANGE_BITS)
		net.Broadcast()
	end

	function meta:SetColor(newColor, ...)
		if not newColor then
			return self:colortree_oldSetColor(newColor)
		end

		local root = getAncestor(self)

		if SERVER then
			updateColor(root)
		end

		return self:colortree_oldSetColor(newColor, ...)
	end

	-- FIXME: Using a timer to bypass load order restrictions is messy. What alternative exists?
	timer.Simple(0, function()
		if meta.SetSubColor then
			if meta.colortree_oldSetSubColor == nil then
				meta.colortree_oldSetSubColor = meta.SetSubColor
			end
			function meta:SetSubColor(ind, newColor)
				local root = getAncestor(self)

				if SERVER then
					updateColor(root)
				end

				---INFO: No need to check nil if we did so earlier
				---@diagnostic disable-next-line
				return self:colortree_oldSetSubColor(ind, newColor)
			end
		end
	end)
end

local lastColorable = NULL
local lastValidColorable = false
function TOOL:Think()
	local currentColorable = self:GetColorable()
	local validColorable = IsValid(currentColorable)

	if currentColorable == lastColorable and validColorable == lastValidColorable then
		return
	end

	if not validColorable then
		self:SetOperation(0)
	else
		self:SetOperation(1)
	end

	if CLIENT then
		self:RebuildControlPanel(currentColorable)
	end
	lastColorable = currentColorable
	lastValidColorable = validColorable
end

---@param newColorable Colorable|Entity
function TOOL:SetColorable(newColorable)
	self:GetWeapon():SetNW2Entity("colortree_entity", newColorable)
end

---@return Colorable|Entity colorable
function TOOL:GetColorable()
	return self:GetWeapon():GetNW2Entity("colortree_entity")
end

---Select the entity to manipulate its entity color tree
---@param tr table|TraceResult
---@return boolean
function TOOL:RightClick(tr)
	self:SetColorable(IsValid(tr.Entity) and tr.Entity or NULL)
	if IsValid(tr.Entity) then
		tr.Entity:CallOnRemove("colortree_removeentity", function()
			if IsValid(self:GetWeapon()) then
				self:SetColorable(NULL)
			end
		end)
	end
	return true
end

if SERVER then
	---Set the colors of the entity by default or through material proxy
	---@param ply Player
	---@param ent Colorable|Entity
	---@param data ColorTreeData
	local function setColor(ply, ent, data)
		if IsValid(ply) then
			ent.colortree_owner = ply
		end

		-- Advanced Colour Tool Condition
		if isAdvancedColorsInstalled(ent) then
			if not ent._adv_colours then
				---@diagnostic disable-next-line
				ent:SetSubColor(0, nil)
			end

			for id, color in pairs(data.colortree_colors) do
				-- Only update the color when its different
				if ent._adv_colours[id] ~= Color(color.r, color.g, color.b, color.a) then
					---@diagnostic disable-next-line
					ent:SetSubColor(id, Color(color.r, color.g, color.b, color.a))
				end
			end

			local mats = ent:GetMaterials()
			for id = 0, #mats - 1 do
				-- Color exists but we're resetting?
				if not data.colortree_colors[id] and ent._adv_colours[id] then
					---@diagnostic disable-next-line
					ent:SetSubColor(id, nil)
				end
			end
		end

		if ent:GetColor() ~= data.colortree_color then
			ent:SetColor(data.colortree_color)
		end
		ent:SetRenderMode(data.colortree_renderMode)
		ent:SetRenderFX(data.colortree_renderFx)
		if data.colortree_color.a < 255 then
			ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
		end

		if data.colortree_proxyColor then
			local hasCloak = false
			local hasGlow = false
			-- If the proxy exists in the data, apply the proxy while transforming the data to a usable format
			for proxyName, proxy in pairs(data.colortree_proxyColor) do
				---@cast proxy MaterialProxy
				---@cast proxy ProxyField
				if not proxy.color then
					continue
				end

				if cloakProxies[proxyName] then
					hasCloak = true
				end
				if glowProxies[proxyName] then
					hasGlow = true
				end

				local transformer = proxyTransformers[proxyName]
				local apply = transformer and transformer.apply
				local transform = transformer and transformer.transform
				if apply and transform then
					apply(ply, ent, transform(proxy))
				end
			end

			-- If the proxy doesn't exist in the data, reset the entity based on the proxy
			for proxyName, transformer in pairs(proxyTransformers) do
				if cloakProxies[proxyName] and hasCloak then
					continue
				end
				if glowProxies[proxyName] and hasGlow then
					continue
				end

				if not data.colortree_proxyColor[proxyName] and transformer.reset then
					transformer.reset(ply, ent, data)
				end
			end
		end

		duplicator.ClearEntityModifier(ent, "colortree")
		duplicator.StoreEntityModifier(ent, "colortree", data)
	end

	---Transform an entity's color tree into data saved for duping
	---@param node ColorTree
	---@returns ColorTreeData
	local function getColorTreeData(node)
		return {
			colortree_color = Color(node.color.r, node.color.g, node.color.b, node.color.a),
			colortree_colors = node.colors,
			colortree_renderMode = node.renderMode,
			colortree_renderFx = node.renderFx,
			colortree_proxyColor = node.proxyColor,
		}
	end

	---Recursively call `setColor` on the tree's descendants
	---@param colorTree ColorTree
	local function setColorWithTree(colorTree, ply)
		setColor(ply, Entity(colorTree.entity), getColorTreeData(colorTree))

		if not colorTree.children or #colorTree.children == 0 then
			return
		end

		for _, node in ipairs(colorTree.children) do
			setColorWithTree(node)
		end
	end

	duplicator.RegisterEntityModifier("colortree", setColor)

	net.Receive("colortree_sync", function(len, ply)
		local treeLen = net.ReadUInt(17)
		local encodedTree = net.ReadData(treeLen)
		local tree = decodeData(encodedTree)

		setColor(ply, Entity(tree.entity), getColorTreeData(tree))
		setColorWithTree(tree, ply)
	end)

	return
else
	net.Receive("colortree_update", function(_, _)
		local entity = net.ReadEntity()
		entity.LastColorChange = net.ReadUInt(CHANGE_BITS)
	end)
end

---@module "colortree.client.colorui"
local ui = include("colortree/client/colorui.lua")

---@type ColorPanelState
local panelState = {
	haloedEntity = NULL,
	haloColor = color_white,
}

---@param cPanel ControlPanel|DForm
---@param colorable Colorable
function TOOL.BuildCPanel(cPanel, colorable)
	local panelChildren = ui.ConstructPanel(cPanel, { colorable = colorable }, panelState)
	ui.HookPanel(panelChildren, { colorable = colorable }, panelState)
end

local TOOL = TOOL
local player = LocalPlayer()
hook.Remove("PreDrawHalos", "colortree_halos")
hook.Add("PreDrawHalos", "colortree_halos", function()
	player = IsValid(player) and player or LocalPlayer()

	local haloedEntity = panelState.haloedEntity
	local haloColor = panelState.haloColor
	local weapon = player:GetWeapon("gmod_tool")

	---INFO: Tools are weapons, but GetWeapon returns a Weapon regardless of the argument, which may not be a tool.
	---Setting this here so linter doesn't complain.
	---@diagnostic disable-next-line
	if IsValid(haloedEntity) and player and weapon and weapon:GetMode() == TOOL:GetMode() then
		halo.Add({ haloedEntity }, haloColor)
	end
end)

TOOL.Information = {
	{ name = "info.0", op = 0 },
	{ name = "info.1", op = 1 },
	{ name = "right.0", op = 0 },
	{ name = "right.1", op = 1 },
}
