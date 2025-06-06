---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")
---@module "colortree.client.proxyconvars"
local proxyConVarMap = include("colortree/client/proxyconvars.lua")
---@module "colortree.shared.proxytransformers"
local pt = include("colortree/shared/proxytransformers.lua")
local proxyTransformers = pt.proxyTransformers

local getValidModelChildren, encodeData, isAdvancedColorsInstalled =
	helpers.getValidModelChildren, helpers.encodeData, helpers.isAdvancedColorsInstalled
local getModelName, getModelNameNice, getModelNodeIconPath =
	helpers.getModelName, helpers.getModelNameNice, helpers.getModelNodeIconPath

local ui = {}

---@type colortree_submaterials
local submaterialFrame = nil

local function getBoolOrFloatConVar(convar, isBool)
	return GetConVar(convar) and Either(isBool, GetConVar(convar):GetBool(), GetConVar(convar):GetFloat())
end

---Update the entity's appearance in the client.
---This happens every tick on the client as opposed to the server, to optimize on the outgoing net rate.
---@param tree ColorTree
local function setColorClient(tree)
	local entity = Entity(tree.entity)
	---@cast entity Colorable
	if not IsValid(entity) then
		return
	end

	-- Advanced Colors
	if next(tree.colors) then
		for id, color in pairs(tree.colors) do
			entity:SetSubColor(id, color)
		end
	else
		entity._adv_colours = {}
	end
	entity._adv_colours_flush = true

	entity:SetColor(tree.color)
	entity:SetRenderMode(tree.renderMode)
	entity:SetRenderFX(tree.renderFx)
	if tree.color.a < 255 then
		entity:SetRenderMode(RENDERMODE_TRANSCOLOR)
	end

	if tree.proxyColor and tree.proxyColor["PlayerColor"] and tree.proxyColor["PlayerColor"].color then
		function entity:GetPlayerColor()
			local v = Vector(
				tree.proxyColor["PlayerColor"].color.r,
				tree.proxyColor["PlayerColor"].color.g,
				tree.proxyColor["PlayerColor"].color.b
			)
			v:Div(255)
			return v
		end
	else
		entity.GetPlayerColor = nil
	end

	for name, transformer in pairs(proxyTransformers) do
		local proxyExists = tree.proxyColor
			and tree.proxyColor[name]
			and tree.proxyColor[name].color
			and transformer.entity
			and entity[transformer.entity.name]
		if not proxyExists then
			continue
		end
		local ent = entity[transformer.entity.name]
		if not IsValid(ent) then
			continue
		end

		for convar, var in pairs(transformer.entity.varMap) do
			if convar == "color" then
				local color = Color(
					tree.proxyColor[name].color.r,
					tree.proxyColor[name].color.g,
					tree.proxyColor[name].color.b,
					tree.proxyColor[name].color.a
				)
				ent:SetColor(color)
				if isvector(ent.Color) then
					local multiplier = 255
					if math.max(ent.Color:Unpack()) <= 1 then
						multiplier = 1
					end
					ent.Color = multiplier * color:ToVector()
				end
				if isvector(ent["Get" .. var](ent)) then
					ent["Set" .. var](ent, color:ToVector())
				end
			else
				if isfunction(ent["Set" .. var]) then
					local val = getBoolOrFloatConVar(convar, isbool(ent["Get" .. var](ent)))
					ent["Set" .. var](ent, val)
				end
			end
		end
	end

	if #tree.children == 0 then
		return
	end
	for _, child in ipairs(tree.children) do
		setColorClient(child)
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

---Reset the colors of a (sub)tree
---@param tree ColorTree
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
---@param tree ColorTree
local function syncTree(tree)
	local data = encodeData(tree)
	net.Start("colortree_sync", true)
	net.WriteUInt(#data, 17)
	net.WriteData(data)
	net.SendToServer()
end

---Get material proxies from the entity if their proxy entity exists. Only supports ItemTintColor
---@param tree ColorTree
---@param entity Colorable
local function getProxyData(tree, entity)
	local ent = entity.ProxyentPaintColor
	if not IsValid(ent) then
		return
	end
	tree.proxyColor = tree.proxyColor or {}
	tree.proxyColor["ItemTintColor"] = {
		color = ent:GetColor(),
		data = {
			["matproxy_tf2itempaint_override"] = ent:GetPaintOverride(), ---@diagnostic disable-line
		},
	}
end

---Get changes to the entity's color tree from an external source
---@param tree ColorTree
local function refreshTree(tree)
	local entity = tree.entity and Entity(tree.entity) or NULL
	---@cast entity Colorable

	tree.color = IsValid(entity) and entity:GetColor() or color_white
	tree.colors = table.Copy(entity._adv_colours) or {}
	getProxyData(tree, entity)

	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		refreshTree(child)
	end
end

---We initialize with bogus values to ensure the paste menu doesn't pop up for some fields
---@type ColorTree
local storedTree = {
	entity = -1,
	---INFO: Type requires Color object, but we're not concerned about it during initialization
	---@diagnostic disable-next-line
	color = {
		a = -1,
	},
	proxyColor = {},
	renderMode = -1,
	renderFx = -1,
	children = {},
}

---Add hooks and color tree pointers
---@param parent ColorTreePanel_Node
---@param entity Colorable|Entity
---@param info ColorTree
---@param rootInfo ColorTree
---@return ColorTreePanel_Node
local function addNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node ColorTreePanel_Node

	node:SetExpanded(true, true)

	function node:DoRightClick()
		if not IsValid(entity) then
			return
		end

		local tree = node.info
		local menu = DermaMenu()
		if tree.proxyColor then
			menu:AddOption("Reset All", function()
				if IsValid(submaterialFrame) then
					submaterialFrame:ClearSelection()
				end
				resetTree(info)
				syncTree(rootInfo)
			end)

			menu:AddSpacer()
		end

		menu:AddOption("Reset Color", function()
			info.color = color_white
			info.colors = {}
			syncTree(rootInfo)
		end)

		if tree.proxyColor then
			for proxy, _ in pairs(tree.proxyColor) do
				menu:AddOption("Reset " .. proxy, function()
					node.info.proxyColor[proxy] = nil
					syncTree(rootInfo)
				end)
			end
		end
		menu:AddSpacer()

		local copyMenu = menu:AddSubMenu("Copy")
		copyMenu:AddOption("All", function()
			storedTree.entity = tree.entity
			storedTree.color = tree.color
			if tree.proxyColor and tree.proxyColor["ItemTintColor"] then
				storedTree.proxyColor["ItemTintColor"] = tree.proxyColor["ItemTintColor"]
			end
			storedTree.renderFx = tree.renderFx
			storedTree.renderMode = tree.renderMode
		end)
		copyMenu:AddSpacer()
		copyMenu:AddOption("Color", function()
			storedTree.entity = tree.entity
			storedTree.color = tree.color
		end)
		if tree.proxyColor and tree.proxyColor["ItemTintColor"] then
			copyMenu:AddOption("Tint", function()
				storedTree.entity = tree.entity
				storedTree.proxyColor["ItemTintColor"] = tree.proxyColor["ItemTintColor"]
			end)
		end
		copyMenu:AddOption("Render FX", function()
			storedTree.entity = tree.entity
			storedTree.renderFx = tree.renderFx
		end)
		copyMenu:AddOption("Render Mode", function()
			storedTree.entity = tree.entity
			storedTree.renderMode = tree.renderMode
		end)

		if storedTree.entity > 0 then
			local pasteMenu = menu:AddSubMenu("Paste")
			if storedTree.color.a > -1 and storedTree.color ~= tree.color then
				pasteMenu:AddOption("Color", function()
					tree.color = storedTree.color
					syncTree(rootInfo)
				end)
			end
			if
				next(storedTree.proxyColor)
				and (
					not tree.proxyColor
					or storedTree.proxyColor["ItemTintColor"].color ~= tree.proxyColor["ItemTintColor"].color
				)
			then
				pasteMenu:AddOption("Proxies", function()
					tree.proxyColor = tree.proxyColor or {}
					tree.proxyColor["ItemTintColor"] = table.Copy(storedTree.proxyColor["ItemTintColor"])
					syncTree(rootInfo)
				end)
			end
			if storedTree.renderFx > -1 and storedTree.renderFx ~= tree.renderFx then
				pasteMenu:AddOption("Render FX", function()
					tree.renderFx = storedTree.renderFx
					syncTree(rootInfo)
				end)
			end
			if storedTree.renderMode > -1 and storedTree.renderMode ~= tree.renderMode then
				pasteMenu:AddOption("Render Mode", function()
					tree.renderMode = storedTree.renderMode
					syncTree(rootInfo)
				end)
			end
			pasteMenu:AddOption("All", function()
				tree.color = storedTree.color
				tree.proxyColor["ItemTintColor"] = table.Copy(storedTree.proxyColor["ItemTintColor"])
				tree.renderFx = storedTree.renderFx
				tree.renderMode = storedTree.renderMode
				syncTree(rootInfo)
			end)
		end

		menu:Open()
	end

	node.Icon:SetImage(getModelNodeIconPath(entity))
	node.info = info

	return node
end

---Construct the color tree
---@param parent Entity
---@return ColorTree
local function entityHierarchy(parent, route)
	local tree = {}
	if not IsValid(parent) then
		return tree
	end

	---@type Colorable[]
	local children = getValidModelChildren(parent)

	for i, child in ipairs(children) do
		if child.GetModel and child:GetModel() ~= "models/error.mdl" then
			table.insert(route, 1, i)
			local node = {
				parent = parent:EntIndex(),
				route = route,
				entity = child:EntIndex(),
				color = child:GetColor(),
				colors = {},
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

---Add all the choices from "RenderMode" or "RenderFX" lists
---@param comboBox DComboBox
---@param renderList any
local function addChoiceFromRenders(comboBox, renderList)
	for key, val in pairs(renderList) do
		local _, renderVal = next(val)
		comboBox:AddChoice(key, renderVal)
	end
end

---@param str string
---@returns string
local function descriptor(str)
	local desc = string.Split(str, "_")
	return desc[#desc]
end

---Change the settings to an addon's UI if it is installed and if the concommands related to them exist
---@param oldSettings table<MaterialProxy, Panel>
---@param category DForm
---@param proxy string
---@returns table<MaterialProxy, Panel>
local function resetProxySettings(oldSettings, category, proxy)
	for _, panel in pairs(oldSettings) do
		if IsValid(panel) then
			panel:Remove()
		end
	end

	local proxyConVars = proxyConVarMap[proxy]
	if not proxyConVars then
		return {}
	end

	local proxyDermas = {}
	for _, proxyConVar in ipairs(proxyConVars) do
		local convar = proxyConVar[1]
		local dermaClass = proxyConVar[2]
		local dermaLabel = proxyConVar[3]

		local derma = vgui.Create(dermaClass, category)
		derma:SetDark(true)
		derma:SetText(Either(dermaLabel and #dermaLabel > 0, dermaLabel, descriptor(convar)))
		derma:SetConVar(convar)
		category:AddItem(derma)
		derma:Dock(TOP)

		proxyDermas[convar] = derma
	end

	return proxyDermas
end

---@param proxyDermas table<MaterialProxy, Panel>
---@returns ProxyData
local function getProxyDataFromEditors(proxyDermas)
	local data = {}

	for name, _ in pairs(proxyDermas) do
		---@diagnostic disable-next-line
		data[name] = GetConVar(name) and GetConVar(name):GetFloat() or 0
	end

	return data
end

---Construct the DTree from the entity color tree
---@param tree ColorTree
---@param nodeParent ColorTreePanel_Node
---@param root ColorTree
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
---@returns ColorTree
local function buildTree(treePanel, entity)
	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:Remove()
	end
	---@type ColorTree
	local hierarchy = {
		entity = entity:EntIndex(),
		color = entity:GetColor(),
		colors = {},
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

local ignore = false

---Set the entity for the submaterial frame.
---
---~~VENT:~~
---
---~~the cringiest thing to exist 🤮🤮🤮, because panels don't update immediately for some reason (need to move the divider to see it happen)
---so we force it with the worst thing possible: recreating the vgui 🤢~~
---@param entity Entity
---@param submaterials table?
---@param panelChildren ColorPanelChildren
---@param panelState ColorPanelState
local function setSubMaterialEntity(entity, submaterials, panelChildren, panelState)
	local lastVisible = false
	if IsValid(submaterialFrame) then
		lastVisible = submaterialFrame:IsVisible()
		submaterialFrame:Remove()
	end

	submaterialFrame = vgui.Create("colortree_submaterials")
	submaterialFrame:SetHelp("#tool.colortree.submaterial.help")
	submaterialFrame:SetVisible(lastVisible)
	submaterialFrame:SetEntity(entity)
	if submaterials then
		submaterialFrame:SetSubMaterials(submaterials)
	end

	-- We'll hook the submaterial frame here for the time being
	if submaterialFrame and IsValid(submaterialFrame) then
		function submaterialFrame:OnSelectedMaterial(id)
			ignore = true
			local node = panelChildren.treePanel:GetSelectedItem()
			if node.info.colors[id] then
				panelChildren.colorPicker.Mixer:SetColor(node.info.colors[id])
			end
			ignore = false
		end

		function submaterialFrame:OnRemovedSubMaterial(id)
			local node = panelChildren.treePanel:GetSelectedItem()
			node.info.colors[id] = nil
			syncTree(panelState.colorTree)
		end

		function submaterialFrame:OnClearSelection()
			local node = panelChildren.treePanel:GetSelectedItem()
			node.info.colors = {}
			syncTree(panelState.colorTree)
		end
	end
end

---@param cPanel DForm|ControlPanel
---@param panelProps ColorPanelProps
---@param panelState ColorPanelState
---@return table
function ui.ConstructPanel(cPanel, panelProps, panelState)
	local colorable = panelProps.colorable

	local treeForm = makeCategory(cPanel, "Entity Hierarchy", "DForm")
	if IsValid(colorable) then
		treeForm:Help("#tool.tooltree.tree")
	end
	treeForm:Help(IsValid(colorable) and "Entity hierarchy for " .. getModelName(colorable) or "No entity selected")
	local treePanel = vgui.Create("DTree", treeForm)
	---@cast treePanel ColorTreePanel
	if IsValid(colorable) then
		panelState.colorTree = buildTree(treePanel, colorable)
	else
		panelState.haloedEntity = NULL
		panelState.colorTree = {} ---@diagnostic disable-line
	end
	treeForm:AddItem(treePanel)
	treePanel:Dock(TOP)
	treePanel:SetSize(treeForm:GetWide(), 250)

	local colorForm = makeCategory(cPanel, "Color", "ControlPanel")
	colorForm:Help("#tool.colortree.color")
	---INFO: ColorPicker also accepts no convars.
	---@diagnostic disable-next-line
	local colorPicker = colorForm:ColorPicker("Color")
	---@cast colorPicker ColorTreePicker
	local renderMode = colorForm:ComboBox("Render Mode", "")
	local renderFx = colorForm:ComboBox("Render FX", "")
	---@cast renderMode DComboBox
	---@cast renderFx DComboBox

	addChoiceFromRenders(renderMode, list.Get("RenderModes"))
	addChoiceFromRenders(renderFx, list.Get("RenderFX"))

	colorForm:Help("Press the up or down arrows on your keyboard to view the most common material proxies")
	local proxySet = colorForm:TextEntry("Proxy:", "")
	---@cast proxySet DTextEntry
	proxySet:SetHistoryEnabled(true)
	proxySet.History = table.GetKeys(proxyConVarMap)
	renderMode:Dock(TOP)
	renderFx:Dock(TOP)
	proxySet:Dock(TOP)

	local proxySettings = makeCategory(colorForm, "Proxy Settings", "DForm")
	local proxyDermas = resetProxySettings({}, proxySettings, proxySet:GetText())

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

	if IsValid(submaterialFrame) then
		submaterialFrame:Remove()
	end

	return {
		treePanel = treePanel,
		colorPicker = colorPicker,
		renderMode = renderMode,
		renderFx = renderFx,
		proxySet = proxySet,
		proxySettings = proxySettings,
		proxyDermas = proxyDermas,
		lock = lock,
		propagate = propagate,
		reset = reset,
	}
end

---@param panelChildren ColorPanelChildren
---@param panelProps ColorPanelProps
---@param panelState ColorPanelState
function ui.HookPanel(panelChildren, panelProps, panelState)
	local colorable = panelProps.colorable

	local treePanel = panelChildren.treePanel
	local colorPicker = panelChildren.colorPicker
	local renderMode = panelChildren.renderMode
	local renderFx = panelChildren.renderFx
	local proxySet = panelChildren.proxySet
	local proxySettings = panelChildren.proxySettings
	local proxyDermas = panelChildren.proxyDermas
	local lock = panelChildren.lock
	local propagate = panelChildren.propagate
	local reset = panelChildren.reset

	function reset:DoClick()
		if IsValid(submaterialFrame) then
			submaterialFrame:ClearSelection()
		end
		resetTree(panelState.colorTree)
		syncTree(panelState.colorTree)
	end

	---@param node ColorTreePanel_Node
	---@param proxy MaterialProxy
	---@param propagate boolean
	local function setProxyData(node, proxy, propagate)
		node.info.proxyColor = node.info.proxyColor or {}
		node.info.proxyColor[proxy] = {
			color = node.info.proxyColor[proxy] and node.info.proxyColor[proxy].color or color_white,
			data = getProxyDataFromEditors(proxyDermas),
		}

		if propagate then
			if node:GetChildNodeCount() == 0 then
				return
			end

			for _, childNode in ipairs(node:GetChildNodes()) do
				setProxyData(childNode, proxy, propagate)
			end
		end
	end

	local shouldSet = false
	local dermaEditors = {}

	function renderMode:OnSelect(_, _, val)
		local selectedNode = treePanel:GetSelectedItem()
		if IsValid(selectedNode) then
			selectedNode.info.renderMode = val
			shouldSet = true
		end
	end

	function renderFx:OnSelect(_, _, val)
		local selectedNode = treePanel:GetSelectedItem()
		if IsValid(selectedNode) then
			selectedNode.info.renderFx = val
			shouldSet = true
		end
	end

	---Anytime the proxy entry changes, hook the new dermas. Return the dermas that have the IsEditing method, for tracking
	---@param dermas table<MaterialProxy, Panel>
	---@param proxy MaterialProxy
	---@return Panel[]
	local function hookProxies(dermas, proxy)
		local editors = {}
		for _, derma in pairs(dermas) do
			if derma:GetName() == "DNumSlider" then
				table.insert(editors, derma)
			end
			function derma:OnValueChanged()
				local selectedNode = treePanel:GetSelectedItem()
				if not selectedNode or not IsValid(Entity(selectedNode.info.entity)) then
					return
				end

				shouldSet = true
				setProxyData(selectedNode, proxy, propagate:GetChecked())
				setColorClient(panelState.colorTree)
			end

			function derma:OnChange()
				local selectedNode = treePanel:GetSelectedItem()
				if not selectedNode or not IsValid(Entity(selectedNode.info.entity)) then
					return
				end

				shouldSet = true
				setProxyData(selectedNode, proxy, propagate:GetChecked())
				setColorClient(panelState.colorTree)
			end
		end
		return editors
	end

	---@param entity Colorable|Entity
	---@param proxy MaterialProxy
	---@param node ColorTreePanel_Node
	---@param shouldIgnore boolean?
	local function setMixerColor(entity, proxy, node, shouldIgnore)
		ignore = Either(shouldIgnore ~= nil, shouldIgnore, false)
		if #proxy > 0 then
			local proxyEnt = proxyTransformers[proxy].entity.name
			local proxyColor = IsValid(entity[proxyEnt]) and entity[proxyEnt]:GetColor()
				or (node.info.proxyColor and node.info.proxyColor[proxy] and node.info.proxyColor[proxy].color)
				or entity:GetColor()
			colorPicker.Mixer:SetColor(proxyColor)
		else
			colorPicker.Mixer:SetColor(node.info.color)
		end
		ignore = false
	end

	---@param newVal string
	function proxySet:OnValueChange(newVal)
		local selectedNode = treePanel:GetSelectedItem()
		if not IsValid(selectedNode) then
			return
		end

		colorPicker:SetLabel("Color " .. newVal)
		setMixerColor(Entity(selectedNode.info.entity), newVal, selectedNode, false)

		proxyDermas = resetProxySettings(proxyDermas, proxySettings, newVal)
		dermaEditors = hookProxies(proxyDermas, newVal)
	end

	dermaEditors = hookProxies(proxyDermas, proxySet:GetText())

	---Update the tree by setting the colors to the pointer nodes
	---@param node ColorTreePanel_Node
	---@param color Color
	---@param propagate boolean
	local function setColor(node, color, propagate)
		local proxy = proxySet:GetText()
		if #proxy > 0 then
			node.info.proxyColor = node.info.proxyColor or {}
			node.info.proxyColor[proxy] = {
				color = color,
				data = getProxyDataFromEditors(proxyDermas),
			}
		else
			node.info.color = color
		end

		if propagate then
			if node:GetChildNodeCount() == 0 then
				return
			end

			for _, childNode in ipairs(node:GetChildNodes()) do
				setColor(childNode, color, propagate)
			end
		end
	end

	---@param newColor Color
	function colorPicker.Mixer:ValueChanged(newColor)
		if ignore then
			return
		end

		local selectedNode = treePanel:GetSelectedItem()
		if not selectedNode or not IsValid(Entity(selectedNode.info.entity)) then
			return
		end

		shouldSet = true

		-- Advanced Colors
		local selected = 0
		if IsValid(submaterialFrame) then
			local selectedSubMaterials, submaterialCount = submaterialFrame:GetSelectedSubMaterials()
			selected = #selectedSubMaterials
			if submaterialCount == 0 then
				selectedNode.info.colors = {}
			end
			for _, id in ipairs(selectedSubMaterials) do
				selectedNode.info.colors[id] = newColor
			end
		end
		-- If we want to manipulate the colors but keep the information about the submaterial colors
		if selected == 0 then
			setColor(selectedNode, newColor, propagate:GetChecked())
		end

		setColorClient(panelState.colorTree)

		local h, s, v = ColorToHSV(newColor)
		panelState.haloColor = HSVToColor(math.abs(h - 180), s, v)
	end

	---@param node ColorTreePanel_Node
	function treePanel:OnNodeSelected(node)
		local entity = Entity(node.info.entity)
		---@cast entity Colorable
		local proxy = proxySet:GetValue()
		if isAdvancedColorsInstalled(entity) then
			setSubMaterialEntity(entity, table.GetKeys(node.info.colors), panelChildren, panelState)
		end
		setMixerColor(entity, proxy, node, true)

		refreshTree(node.info)

		panelState.haloedEntity = entity
	end

	-- Initialize with our selection
	if IsValid(treePanel) and IsValid(treePanel.ancestor) then
		treePanel:SetSelectedItem(treePanel.ancestor)
		-- FIXME: Creates the submaterial frame twice. Could we circumvent this?
		if isAdvancedColorsInstalled(colorable) then
			setSubMaterialEntity(colorable, table.GetKeys(colorable._adv_colours or {}), panelChildren, panelState)
		end
		refreshTree(panelState.colorTree)
	end

	---@param panel DPanel
	local function overrideMousePressed(panel)
		local oldPressed = panel.OnMousePressed
		function panel:OnMousePressed(mcode)
			oldPressed(self, mcode)
			self.dragging = true
		end

		local oldReleased = panel.OnMouseReleased
		function panel:OnMouseReleased(mcode)
			oldReleased(self, mcode)
			self.dragging = false
		end

		function panel:IsEditing()
			return self.dragging
		end
	end

	-- The alpha and RGB bars don't have an IsEditing function, so we have to override them
	overrideMousePressed(colorPicker.Mixer.Alpha)
	overrideMousePressed(colorPicker.Mixer.RGB)

	---If we are moving a `DNumSlider` or a `DColorMixer`, we are editing.
	---@param editors Panel[]|DNumSlider[]
	---@return boolean
	local function checkEditing(editors)
		if
			colorPicker.Mixer.HSV:IsEditing()
			or colorPicker.Mixer.Alpha:IsEditing()
			or colorPicker.Mixer.RGB:IsEditing()
		then
			return true
		end

		for _, editor in ipairs(editors) do
			if editor:IsEditing() then
				return true
			end
		end
		return false
	end

	hook.Remove("OnContextMenuOpen", "colortree_hookcontext")
	-- Advanced Colors
	if IsValid(submaterialFrame) then
		hook.Add("OnContextMenuOpen", "colortree_hookcontext", function()
			local tool = LocalPlayer():GetTool()
			if tool and tool.Mode == "colortree" then
				submaterialFrame:SetVisible(true)
				submaterialFrame:MakePopup()
			end
		end)
	end

	hook.Remove("OnContextMenuClose", "colortree_hookcontext")
	-- Advanced Colors
	if IsValid(submaterialFrame) then
		hook.Add("OnContextMenuClose", "colortree_hookcontext", function()
			submaterialFrame:SetVisible(false)
			submaterialFrame:SetMouseInputEnabled(false)
			submaterialFrame:SetKeyboardInputEnabled(false)
		end)
	end

	local lastThink = CurTime()
	-- ENT.LastColorChange is always at least 0. We set it to -1 to ensure that we will always
	-- refresh the tree at the start
	local lastColorChange = -1
	timer.Remove("colortree_think")
	if not IsValid(colorable) then
		return
	end

	timer.Create("colortree_think", 0, -1, function()
		local now = CurTime()
		local editing = checkEditing(dermaEditors)
		if now - lastThink > 0.1 and shouldSet and not editing then
			syncTree(panelState.colorTree)
			lastThink = now
			shouldSet = false
		end

		-- Whether we should receive updates from the server or not.
		-- Useful if we want an external source to modify the colors of the entity
		if lock:GetChecked() then
			return
		end

		-- Don't check color children until we are done editing the colors
		if editing then
			return
		end

		if not IsValid(colorable) then
			return
		end

		local currentColorChange = colorable.LastColorChange

		-- Colors changed? Update the color picker to indicate this
		if currentColorChange ~= lastColorChange then
			refreshTree(panelState.colorTree)
			ignore = true

			if IsValid(submaterialFrame) then
				local selectedNode = treePanel:GetSelectedItem()
				local entity = Entity(selectedNode.info.entity)
				---@cast entity Colorable

				local selected, subcount = submaterialFrame:GetSelectedSubMaterials()
				for _, id in ipairs(selected) do
					colorPicker.Mixer:SetColor(entity._adv_colours[id] or color_white)
				end
			end

			ignore = false
			lastColorChange = currentColorChange
		end
	end)
	timer.Start("colortree_think")
end

return ui
