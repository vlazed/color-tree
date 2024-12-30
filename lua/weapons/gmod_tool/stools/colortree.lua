TOOL.Category = "Render"
TOOL.Name = "#tool.colortree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["proxy"] = ""
TOOL.ClientConVar["lock"] = 0
TOOL.ClientConVar["propagate"] = 0

local DEFAULT_PLAYER_COLOR = Vector(62 / 255, 88 / 255, 106 / 255)

local ENTITY_FILTER = {
	proxyent_tf2itempaint = true,
	proxyent_tf2critglow = true,
}

local MODEL_FILTER = {
	["models/error.mdl"] = true,
}

---Get a filtered array of the entity's children
---@param entity Entity
---@return Entity[]
local function getValidModelChildren(entity)
	local filteredChildren = {}
	for i, child in ipairs(entity:GetChildren()) do
		if child.GetModel and not MODEL_FILTER[child:GetModel()] and not ENTITY_FILTER[child:GetClass()] then
			table.insert(filteredChildren, child)
		end
	end
	return filteredChildren
end

---@param tbl table
---@return string
local function encodeData(tbl)
	return util.Compress(util.TableToJSON(tbl))
end

---@param data string
---@return table
local function decodeData(data)
	return util.JSONToTable(util.Decompress(data))
end

---@type ProxyTransformer
local cloakFuncs = {
	apply = GiveMatproxyTF2CloakEffect, ---@diagnostic disable-line
	transform = function(data)
		return {
			TintR = data.color.r,
			TintG = data.color.g,
			TintB = data.color.b,
			Anim = 1,
		}
	end,
	reset = function(ply, ent, data)
		local old = ent.ProxyentCloakEffect
		if IsValid(old) then
			old:Remove()
			ent.ProxyentCloakEffect = nil
		end
		duplicator.ClearEntityModifier(ent, "MatproxyTF2ItemPaint")
	end,
}

---Mapping of material proxies to function tables
---@type ProxyTransformers
local proxyTransformers = {
	["ItemTintColor"] = {
		apply = GiveMatproxyTF2ItemPaint, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
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
		apply = GiveMatproxyTF2CritGlow, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				JarateSparks = true,
				JarateColorable = true,
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
			}
		end,
		reset = function(ply, ent, data)
			local old = ent.ProxyentCritGlow
			if IsValid(old) then
				old:Remove()
				ent.ProxyentCritGlow = nil
			end
			duplicator.ClearEntityModifier(ent, "MatproxyTF2CritGlow")
		end,
	},
	["spy_invis"] = cloakFuncs,
	["invis"] = cloakFuncs,
	["weapon_invis"] = cloakFuncs,
	["building_invis"] = cloakFuncs,
	["ModelGlowColor"] = {
		apply = GiveMatproxyTF2CritGlow, ---@diagnostic disable-line
		transform = function(proxy)
			return {
				ColorableSparks = true,
				ColorR = proxy.color.r,
				ColorG = proxy.color.g,
				ColorB = proxy.color.b,
			}
		end,
		reset = function(ply, ent, data)
			local old = ent.ProxyentCritGlow
			if IsValid(old) then
				old:Remove()
				ent.ProxyentCritGlow = nil
			end
			duplicator.ClearEntityModifier(ent, "MatproxyTF2CritGlow")
		end,
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

---Set the colors of the entity by default or throuregh material proxy
---@param ply Player
---@param ent Colorable|Entity
---@param data ColorTreeData
local function setColor(ply, ent, data)
	PrintTable(data)
	if IsValid(ply) then
		ent.colortree_owner = ply
	end
	ent:SetColor(data.colortree_color)
	ent:SetRenderMode(data.colortree_renderMode)
	ent:SetRenderFX(data.colortree_renderFx)
	if data.colortree_color.a < 255 then
		ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
	end
	if data.colortree_proxyColor then
		-- If the proxy exists in the data, apply the proxy while transforming the data to a usable format
		for proxyName, proxy in pairs(data.colortree_proxyColor) do
			---@cast proxy MaterialProxy
			---@cast proxy ProxyField
			if not proxy.color then
				continue
			end

			if proxyTransformers[proxyName] and proxyTransformers[proxyName].apply then
				proxyTransformers[proxyName].apply(ply, ent, proxyTransformers[proxyName].transform(proxy))
			end
		end
		-- If the proxy doesn't exist in the data, reset the entity based on the proxy
		for proxyName, transformer in pairs(proxyTransformers) do
			if not data.colortree_proxyColor[proxyName] and transformer.reset then
				transformer.reset(ply, ent, data)
			end
		end
	end

	duplicator.StoreEntityModifier(ent, "colortree", data)
end
if SERVER then
	duplicator.RegisterEntityModifier("colortree", setColor)
end

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

---@param tr table|TraceResult
---@return boolean
function TOOL:RightClick(tr)
	self:SetColorable(tr.Entity)
	return true
end

---Transform an entity's color tree into data saved for duping
---@param node DescendantTree
---@returns ColorTreeData
local function getColorTreeData(node)
	return {
		colortree_color = node.color,
		colortree_renderMode = node.renderMode,
		colortree_renderFx = node.renderFx,
		colortree_proxyColor = node.proxyColor,
	}
end

---Recursively call `setColor` on the tree's descendants
---@param descendantTree DescendantTree
local function setColorWithTree(descendantTree, ply)
	if not descendantTree.children or #descendantTree.children == 0 then
		return
	end

	for _, node in ipairs(descendantTree.children) do
		setColor(ply, Entity(node.entity), getColorTreeData(node))
		if node.children and #node.children > 0 then
			setColorWithTree(node.children)
		end
	end
end

if SERVER then
	util.AddNetworkString("colortree_sync")
	util.AddNetworkString("colortree_action")
	net.Receive("colortree_sync", function(len, ply)
		local treeLen = net.ReadUInt(17)
		local encodedTree = net.ReadData(treeLen)
		local tree = decodeData(encodedTree)

		setColor(ply, Entity(tree.entity), getColorTreeData(tree))
		setColorWithTree(tree, ply)
	end)

	net.Receive("colortree_action", function(_, ply)
		---@type Colorable|Entity
		local entity = net.ReadEntity()
		local action = net.ReadString()

		if entity.colortree_owner == ply and isfunction(entity[action]) then
			entity[action](entity)
		end
	end)

	return
end

---Construct the color tree
---@param parent Entity
---@return DescendantTree
local function entityHierarchy(parent, route)
	local tree = {}
	if not IsValid(parent) then
		return tree
	end

	---@type Entity[]
	local children = getValidModelChildren(parent)

	for i, child in ipairs(children) do
		if child.GetModel and child:GetModel() ~= "models/error.mdl" then
			table.insert(route, 1, i)
			local node = {
				parent = parent:EntIndex(),
				route = route,
				entity = child:EntIndex(),
				color = child:GetColor(),
				children = entityHierarchy(child, route),
				renderFx = child:GetRenderFX(),
				renderMode = child:GetRenderMode(),
			}
			table.insert(tree, node)
			route = {}
		end
	end

	return tree
end

---Get a nicely formatted model name
---@param entity Entity
---@return string
local function getModelNameNice(entity)
	local mdl = string.Split(entity:GetModel() or "", "/")
	mdl = mdl[#mdl]
	return string.NiceName(string.sub(mdl, 1, #mdl - 4))
end

---Get the model name without the path
---@param entity Entity
---@return string
local function getModelName(entity)
	local mdl = string.Split(entity:GetModel(), "/")
	mdl = mdl[#mdl]
	return mdl
end

---Grab the entity's model icon
---@source https://github.com/NO-LOAFING/AdvBonemerge/blob/371b790d00d9bcbb62845ce8785fc6b98fbe8ef4/lua/weapons/gmod_tool/stools/advbonemerge.lua#L1079
---@param ent Entity
---@return string iconPath
local function getModelNodeIconPath(ent)
	local skinid = ent:GetSkin() or 0
	local modelicon = "spawnicons/" .. string.StripExtension(ent:GetModel()) .. ".png"
	if skinid > 0 then
		modelicon = "spawnicons/" .. string.StripExtension(ent:GetModel()) .. "_skin" .. skinid .. ".png"
	end

	if not file.Exists("materials/" .. modelicon, "GAME") then
		modelicon = "icon16/bricks.png"
	end
	return modelicon
end

---Reset the colors of a (sub)tree
---@param tree DescendantTree
local function resetTree(tree)
	tree.color = color_white
	tree.proxyColor = {}
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		resetTree(child)
	end
end

---Send the entity color tree to the server for coloring
---@param tree DescendantTree
local function syncTree(tree)
	local data = encodeData(tree)
	net.Start("colortree_sync", true)
	net.WriteUInt(#data, 17)
	net.WriteData(data)
	net.SendToServer()
end

---Get changes to the entity's color tree from an external source
---@param tree DescendantTree
local function refreshTree(tree)
	local entity = tree.entity and Entity(tree.entity) or NULL
	tree.color = IsValid(entity) and entity:GetColor() or color_white
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		refreshTree(child)
	end
end

---Add hooks and color tree pointers
---@param parent ColorTreePanel_Node
---@param entity Colorable|Entity
---@param info DescendantTree
---@param rootInfo DescendantTree
---@return ColorTreePanel_Node
local function addNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node ColorTreePanel_Node

	function node:DoRightClick()
		if not IsValid(entity) then
			return
		end

		local menu = DermaMenu()
		if node.info.proxyColor then
			menu:AddOption("Reset All", function()
				resetTree(info)
				syncTree(rootInfo)
			end)

			menu:AddSpacer()
		end

		menu:AddOption("Reset Color", function()
			info.color = color_white
			syncTree(rootInfo)
		end)

		if node.info.proxyColor then
			for proxy, _ in pairs(node.info.proxyColor) do
				menu:AddOption("Reset " .. proxy, function()
					node.info.proxyColor[proxy] = nil
					syncTree(rootInfo)
				end)
			end
		end

		menu:Open()
	end

	node.Icon:SetImage(getModelNodeIconPath(entity))
	node.info = info

	return node
end

---Construct the DTree from the entity color tree
---@param tree DescendantTree
---@param nodeParent ColorTreePanel_Node
---@param root DescendantTree
local function hierarchyPanel(tree, nodeParent, root)
	for _, child in ipairs(tree) do
		local childEntity = Entity(child.entity)
		if not IsValid(childEntity) or not childEntity.GetModel or not childEntity:GetModel() then
			continue
		end

		local node = addNode(nodeParent, childEntity, child, root)

		if #child.children > 0 then
			hierarchyPanel(child.children, node, root)
		end
	end
end

---Construct the `entity`'s color tree
---@param treePanel ColorTreePanel
---@param entity Colorable|Entity
---@returns DescendantTree
local function buildTree(treePanel, entity)
	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:Remove()
	end
	---@type DescendantTree
	local hierarchy = {
		entity = entity:EntIndex(),
		color = entity:GetColor(),
		renderFx = entity:GetRenderFX(),
		renderMode = entity:GetRenderMode(),
		children = entityHierarchy(entity, {}),
	}

	---@type ColorTreePanel_Node
	---@diagnostic disable-next-line
	treePanel.ancestor = addNode(treePanel, entity, hierarchy, hierarchy)
	treePanel.ancestor.Icon:SetImage(getModelNodeIconPath(entity))
	treePanel.ancestor.info = hierarchy
	hierarchyPanel(hierarchy.children, treePanel.ancestor, hierarchy)

	return hierarchy
end

---Add all the choices from "RenderMode" or "RenderFX" lists
---@param comboBox DComboBox
---@param renderList any
local function addChoiceFromRenders(comboBox, renderList)
	for key, val in pairs(renderList) do
		local _, renderVal = next(val)
		comboBox:AddChoice(key, renderVal)
	end
end

---Helper for DForm
---@param cPanel ControlPanel|DForm
---@param name string
---@param type "ControlPanel"|"DForm"
---@return ControlPanel|DForm
local function makeCategory(cPanel, name, type)
	---@type DForm|ControlPanel
	local category = vgui.Create(type, cPanel)

	category:SetLabel(name)
	cPanel:AddItem(category)
	return category
end

---Construct a flat array of the entity's descendant colors
local function getColorChildrenIdentifier(entity, tbl)
	if not IsValid(entity) then
		return {}
	end

	local children = getValidModelChildren(entity)
	for _, child in ipairs(children) do
		table.insert(tbl, child:GetColor())
		getColorChildrenIdentifier(child, tbl)
	end

	return tbl
end

---Check if every descendant's color is equal to some other descendant color
local function isColorChildrenEqual(t1, t2)
	if #t1 ~= #t2 then
		return false
	end

	for i = 1, #t1 do
		if t1[i] ~= t2[i] then
			return false
		end
	end

	return true
end

local haloedEntity = NULL
local haloColor = color_white

---Change the settings to an addon's UI if it is installed and if the concommands related to them exist
---@param category DForm
---@param proxy string
local function resetProxySettings(category, proxy)
	for _, panel in ipairs(category:GetChildren()) do
		if IsValid(panel) and panel:GetName() ~= "DCategoryHeader" then
			panel:Remove()
		end
	end
end

---@param proxy string
---@returns ProxyData
local function getProxyData(proxy)
	local data = {}
	return data
end

---@param cPanel ControlPanel|DForm
---@param colorable Colorable
function TOOL.BuildCPanel(cPanel, colorable)
	local treeForm = makeCategory(cPanel, "Entity Hierarchy", "DForm")
	treeForm:Help(IsValid(colorable) and "Entity hierarchy for " .. getModelName(colorable) or "No entity selected")
	local treePanel = vgui.Create("DTree", treeForm)
	local descendantTree = {}
	---@cast treePanel ColorTreePanel
	if IsValid(colorable) then
		descendantTree = buildTree(treePanel, colorable)
	else
		haloedEntity = NULL
	end
	treeForm:AddItem(treePanel)
	treePanel:Dock(TOP)
	treePanel:SetSize(treeForm:GetWide(), 250)

	local colorForm = makeCategory(cPanel, "Color", "ControlPanel")
	colorForm:Help("#tool.colortree.color")
	local colorPicker = colorForm:ColorPicker("Color", "colour_r", "colour_g", "colour_b", "colour_a")
	---@cast colorPicker ColorTreePicker
	local renderMode = colorForm:ComboBox("Render Mode", "")
	local renderFx = colorForm:ComboBox("Render FX", "")
	---@cast renderMode DComboBox
	---@cast renderFx DComboBox

	addChoiceFromRenders(renderMode, list.Get("RenderModes"))
	addChoiceFromRenders(renderFx, list.Get("RenderFX"))

	colorForm:Help("Press the up or down arrows on your keyboard to view the most common material proxies")
	local proxySet = colorForm:TextEntry("Proxy:", "colortree_proxy")
	---@cast proxySet DTextEntry
	proxySet:SetHistoryEnabled(true)
	proxySet.History = {
		"PlayerColor",
		"ItemTintColor",
		"YellowLevel",
		"ModelGlowColor",
	}
	renderMode:Dock(TOP)
	renderFx:Dock(TOP)
	proxySet:Dock(TOP)

	local proxySettings = makeCategory(colorForm, "Proxy Settings", "DForm")
	resetProxySettings(proxySettings, proxySet:GetText())

	local settings = makeCategory(cPanel, "Settings", "DForm")

	---@type DCheckBoxLabel
	---@diagnostic disable-next-line
	local lock = settings:CheckBox("#tool.colortree.lock", "colortree_lock")
	lock:SetTooltip("#tool.colortree.lock.tooltip")
	---@type DCheckBoxLabel
	---@diagnostic disable-next-line
	local propagate = settings:CheckBox("#tool.colortree.propagate", "colortree_propagate")
	propagate:SetTooltip("#tool.colortree.propagate.tooltip")
	---@type DButton
	---@diagnostic disable-next-line
	local reset = settings:Button("Reset All Colors", "")

	colorPicker:SetLabel("Color " .. proxySet:GetText())
	function reset:DoClick()
		resetTree(descendantTree)
		syncTree(descendantTree)
	end

	function proxySet:OnValueChange(newVal)
		resetProxySettings(proxySettings, newVal)
	end

	---@param newColor Color
	---@diagnostic disable-next-line
	function colorPicker.Mixer:ValueChanged(newColor)
		local selectedNode = treePanel:GetSelectedItem()
		if not selectedNode or not IsValid(Entity(selectedNode.info.entity)) then
			return
		end

		---@param node ColorTreePanel_Node
		local function setColor(node)
			local proxy = proxySet:GetText()
			if #proxy > 0 then
				node.info.proxyColor = node.info.proxyColor or {}
				node.info.proxyColor[proxySet:GetText()] = {
					color = newColor,
					data = getProxyData(proxy),
				}
			else
				node.info.color = newColor
			end
		end

		setColor(selectedNode)
		if propagate:GetChecked() then
			for _, childNode in ipairs(selectedNode:GetChildNodes()) do
				setColor(childNode)
			end
		end

		local h, s, v = ColorToHSV(newColor)
		haloColor = HSVToColor(math.abs(h - 180), s, v)
		syncTree(descendantTree)
	end
	---@param node ColorTreePanel_Node
	function treePanel:OnNodeSelected(node)
		haloedEntity = Entity(node.info.entity)
	end

	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:SetSelected(true)
	end

	local lastColor = {}
	timer.Create("colortree_think", 0, -1, function()
		if lock:GetChecked() then
			return
		end

		local currentColor = getColorChildrenIdentifier(colorable, {})

		if not isColorChildrenEqual(lastColor, currentColor) then
			refreshTree(descendantTree)
			lastColor = currentColor
		end
	end)
end

hook.Add("PreDrawHalos", "colortree_halos", function()
	if IsValid(haloedEntity) then
		halo.Add({ haloedEntity }, haloColor)
	end
end)

TOOL.Information = {
	{ name = "info", operation = 0 },
	{ name = "right", operation = 0 },
}
