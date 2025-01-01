TOOL.Category = "Render"
TOOL.Name = "#tool.colortree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["proxy"] = ""
TOOL.ClientConVar["lock"] = 0
TOOL.ClientConVar["propagate"] = 0

---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")
---@module "colortree.shared.proxyTransformers"
local pt = include("colortree/shared/proxyTransformers.lua")

local cloakProxies, glowProxies, proxyTransformers = pt.cloakProxies, pt.glowProxies, pt.proxyTransformers

local decodeData = helpers.decodeData

local lastColorable = NULL
function TOOL:Think()
	local currentColorable = self:GetColorable()
	if currentColorable == NULL then
		self:SetOperation(0)
	else
		self:SetOperation(1)
	end

	if currentColorable == lastColorable then
		return
	end

	if CLIENT then
		self:RebuildControlPanel(currentColorable)
	end
	lastColorable = currentColorable
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
	return true
end

if SERVER then
	---Set the colors of the entity by default or throuregh material proxy
	---@param ply Player
	---@param ent Colorable|Entity
	---@param data ColorTreeData
	local function setColor(ply, ent, data)
		if IsValid(ply) then
			ent.colortree_owner = ply
		end

		if data.colortree_colors and next(data.colortree_colors) then
			for id, color in pairs(data.colortree_colors) do
				---@diagnostic disable-next-line
				ent:SetSubColor(id, Color(color.r, color.g, color.b, color.a))
			end
		end
		ent:SetColor(data.colortree_color)
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
			colortree_color = node.color,
			colortree_colors = node.colors,
			colortree_renderMode = node.renderMode,
			colortree_renderFx = node.renderFx,
			colortree_proxyColor = node.proxyColor,
		}
	end

	---Recursively call `setColor` on the tree's descendants
	---@param colorTree ColorTree
	local function setColorWithTree(colorTree, ply)
		if not colorTree.children or #colorTree.children == 0 then
			return
		end

		for _, node in ipairs(colorTree.children) do
			setColor(ply, Entity(node.entity), getColorTreeData(node))
			if node.children and #node.children > 0 then
				setColorWithTree(node.children)
			end
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

hook.Remove("PreDrawHalos", "colortree_halos")
hook.Add("PreDrawHalos", "colortree_halos", function()
	local haloedEntity = panelState.haloedEntity
	local haloColor = panelState.haloColor
	if IsValid(haloedEntity) then
		halo.Add({ haloedEntity }, haloColor)
	end
end)

TOOL.Information = {
	{ name = "info", operation = 0 },
	{ name = "right", operation = 0 },
}
