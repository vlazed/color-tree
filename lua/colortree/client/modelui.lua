---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local getValidModelChildren, encodeData = helpers.getValidModelChildren, helpers.encodeData
local getModelName, getModelNameNice, getModelNodeIconPath =
	helpers.getModelName, helpers.getModelNameNice, helpers.getModelNodeIconPath

local ui = {}

---Update the entity's appearance in the client.
---This happens every tick on the client as opposed to the server, to optimize on the outgoing net rate.
---@param tree ModelTree
local function setModelClient(tree)
	local entity = Entity(tree.entity)
	if not IsValid(entity) then
		return
	end

	if entity:GetModel() ~= tree.model then
		entity:SetModel(tree.model)
	end
	entity:SetBodyGroups(tree.bodygroups)
	entity:SetSkin(tree.skin)

	if not tree.children and #tree.children == 0 then
		return
	end
	for _, child in ipairs(tree.children) do
		setModelClient(child)
	end
end

---@param ent Entity
---@return string
local function getBodygroups(ent)
	local bodygroups = ""
	if ent:GetNumBodyGroups() == 0 then
		return bodygroups
	end

	for i = 0, ent:GetNumBodyGroups() do
		bodygroups = bodygroups .. tostring(ent:GetBodygroup(i))
	end
	return bodygroups
end

---@param entity Entity
---@return table
local function getModelDefaults(entity)
	local csModel = ClientsideModel(entity:GetModel())
	local defaultProps = {
		defaultModel = csModel:GetModel(),
		defaultSkin = csModel:GetSkin(),
		defaultBodygroups = getBodygroups(csModel),
	}
	csModel:Remove()

	return defaultProps
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

---Reset the models of a (sub)tree
---@param tree ModelTree
local function resetTree(tree)
	tree.model = tree.defaultModel
	tree.skin = tree.defaultSkin
	tree.bodygroups = tree.defaultBodygroups
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		resetTree(child)
	end
end

---Send the entity model tree to the server
---@param tree ModelTree
local function syncTree(tree)
	local data = encodeData(tree)
	net.Start("modeltree_sync", true)
	net.WriteUInt(#data, 17)
	net.WriteData(data)
	net.SendToServer()
end

---Get changes to the entity's model tree from an external source
---@param tree ModelTree
local function refreshTree(tree)
	local entity = tree.entity and Entity(tree.entity) or NULL
	tree.model = IsValid(entity) and entity:GetModel() or tree.defaultModel
	tree.skin = IsValid(entity) and entity:GetSkin() or tree.defaultSkin
	tree.bodygroups = IsValid(entity) and getBodygroups(entity) or tree.defaultBodygroups
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		refreshTree(child)
	end
end

---@type ModelTree
local storedTree = {
	entity = -1,
	defaultModel = "",
	defaultSkin = 0,
	defaultBodygroups = "",
	model = "",
	bodygroups = "",
	skin = -1,
	children = {},
}

---Add hooks and model tree pointers
---@param parent ModelTreePanel_Node
---@param entity Entity
---@param info ModelTree
---@param rootInfo ModelTree
---@return ModelTreePanel_Node
local function addNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node ModelTreePanel_Node

	node:SetExpanded(true, true)

	function node:DoRightClick()
		if not IsValid(entity) then
			return
		end

		local menu = DermaMenu()
		menu:AddOption("Reset All", function()
			resetTree(info)
			syncTree(rootInfo)
		end)
		menu:AddSpacer()

		local copyMenu = menu:AddSubMenu("Copy")
		copyMenu:AddOption("All", function()
			storedTree.entity = node.info.entity
			storedTree.skin = node.info.skin
			storedTree.bodygroups = node.info.bodygroups
			storedTree.model = node.info.model
		end)
		copyMenu:AddSpacer()
		copyMenu:AddOption("Skin", function()
			storedTree.entity = node.info.entity
			storedTree.skin = node.info.skin
		end)
		copyMenu:AddOption("Bodygroups", function()
			storedTree.entity = node.info.entity
			storedTree.bodygroups = node.info.bodygroups
		end)
		copyMenu:AddOption("Model", function()
			storedTree.entity = node.info.entity
			storedTree.model = node.info.model
		end)
		if storedTree.entity > 0 then
			local pasteMenu = menu:AddSubMenu("Paste")
			if storedTree.skin > -1 and storedTree.skin ~= node.info.skin then
				pasteMenu:AddOption("Skin", function()
					node.info.skin = storedTree.skin
					syncTree(rootInfo)
				end)
			end
			if #storedTree.bodygroups > 0 and storedTree.bodygroups ~= node.info.bodygroups then
				pasteMenu:AddOption("Bodygroups", function()
					node.info.bodygroups = storedTree.bodygroups
					syncTree(rootInfo)
				end)
			end
			if #storedTree.model > 0 and storedTree.model ~= node.info.model then
				pasteMenu:AddOption("Model", function()
					node.info.model = storedTree.model
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

---Construct the model tree
---@param parent Entity
---@return ModelTree
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
			local defaultProps = getModelDefaults(child)

			---@type ModelTree
			local node = {
				parent = parent:EntIndex(),
				route = route,
				entity = child:EntIndex(),
				model = child:GetModel(),
				defaultModel = defaultProps.defaultModel,
				defaultSkin = defaultProps.defaultSkin,
				defaultBodygroups = defaultProps.defaultBodygroups,
				children = entityHierarchy(child, route),
				skin = child:GetRenderFX(),
				bodygroups = getBodygroups(child),
			}
			table.insert(tree, node)
			route = {}
		end
	end

	return tree
end

---Construct the DTree from the entity model tree
---@param tree ModelTree
---@param nodeParent ModelTreePanel_Node
---@param root ModelTree
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

---Construct the `entity`'s model tree
---@param treePanel ModelTreePanel
---@param entity Entity
---@returns ModelTree
local function buildTree(treePanel, entity)
	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:Remove()
	end

	local defaultProps = getModelDefaults(entity)

	---@type ModelTree
	local hierarchy = {
		entity = entity:EntIndex(),
		model = entity:GetModel(),
		skin = entity:GetSkin(),
		bodygroups = getBodygroups(entity),
		defaultModel = defaultProps.defaultModel,
		defaultSkin = defaultProps.defaultSkin,
		defaultBodygroups = defaultProps.defaultBodygroups,
		children = entityHierarchy(entity, {}),
	}

	---@type ModelTreePanel_Node
	---@diagnostic disable-next-line
	treePanel.ancestor = addNode(treePanel, entity, hierarchy, hierarchy)
	treePanel.ancestor.Icon:SetImage(getModelNodeIconPath(entity))
	treePanel.ancestor.info = hierarchy
	hierarchyPanel(hierarchy.children, treePanel.ancestor, hierarchy)

	return hierarchy
end

---@param cPanel DForm|ControlPanel
---@param panelProps ModelPanelProps
---@param panelState ModelPanelState
---@return table
function ui.ConstructPanel(cPanel, panelProps, panelState)
	local modelEntity = panelProps.modelEntity

	local treeForm = makeCategory(cPanel, "Entity Hierarchy", "DForm")
	if IsValid(modelEntity) then
		treeForm:Help("#tool.tooltree.tree")
	end
	treeForm:Help(IsValid(modelEntity) and "Entity hierarchy for " .. getModelName(modelEntity) or "No entity selected")
	local treePanel = vgui.Create("DTree", treeForm)
	---@cast treePanel ModelTreePanel
	if IsValid(modelEntity) then
		panelState.modelTree = buildTree(treePanel, modelEntity)
	else
		panelState.haloedEntity = NULL
		panelState.modelTree = {} ---@diagnostic disable-line
	end
	treeForm:AddItem(treePanel)
	treePanel:Dock(TOP)
	treePanel:SetSize(treeForm:GetWide(), 250)

	local modelForm = makeCategory(cPanel, "Model", "ControlPanel")
	modelForm:Help("#tool.modeltree.model")
	local modelEntry = vgui.Create("DTextEntry", cPanel)
	---@cast modelEntry DTextEntry
	modelForm:AddItem(modelEntry)
	modelEntry:Dock(TOP)

	if IsValid(modelEntity) then
		modelEntry:SetText(modelEntity:GetModel())
	end

	local settings = makeCategory(cPanel, "Settings", "DForm")

	---@type DCheckBoxLabel
	---@diagnostic disable-next-line
	local lock = settings:CheckBox("#tool.modeltree.lock", "modeltree_lock")
	lock:SetTooltip("#tool.modeltree.lock.tooltip")

	---@type DCheckBoxLabel
	---@diagnostic disable-next-line
	local propagate = settings:CheckBox("#tool.modeltree.propagate", "modeltree_propagate")
	propagate:SetTooltip("#tool.modeltree.propagate.tooltip")

	return {
		treePanel = treePanel,
		modelForm = modelForm,
		modelEntry = modelEntry,
		lock = lock,
		propagate = propagate,
	}
end

---@param panelChildren ModelPanelChildren
---@param panelProps ModelPanelProps
---@param panelState ModelPanelState
function ui.HookPanel(panelChildren, panelProps, panelState)
	local modelEntity = panelProps.modelEntity

	local treePanel = panelChildren.treePanel
	local modelForm = panelChildren.modelForm
	local modelEntry = panelChildren.modelEntry
	local lock = panelChildren.lock
	local propagate = panelChildren.propagate

	local dermaEditors = {}
	local shouldSet = false

	---@param tree ModelTree
	---@param newSkin integer
	local function setSkin(tree, newSkin)
		local ent = Entity(tree.entity)
		tree.skin = newSkin % ent:SkinCount()
		if not propagate:GetChecked() then
			return
		end
		if not tree.children or #tree.children == 0 then
			return
		end

		for _, child in ipairs(tree.children) do
			setSkin(child, newSkin)
		end
	end

	---Change the settings when we select another model to edit
	---@param oldEditors Panel[]
	---@param category DForm
	---@param tree ModelTree
	---@returns Panel[]
	local function resetModelSettings(oldEditors, category, tree)
		for _, panel in ipairs(oldEditors) do
			if IsValid(panel) then
				panel:Remove()
			end
		end

		-- During a model change, the entity's model is usually not ready for the client, so we'll get it immediately
		-- using a ClientsideModel
		local csModel = ClientsideModel(tree.model)
		local editors = {}
		local skins = csModel:SkinCount()

		if skins > 1 then
			local skinSlider = category:NumSlider("Skin", "", 0, skins - 1, 0)
			---@cast skinSlider DNumSlider
			skinSlider:SetValue(tree.skin)

			function skinSlider:OnValueChanged(newVal)
				local node = treePanel:GetSelectedItem()
				newVal = math.modf(newVal)

				setSkin(tree, newVal)
				shouldSet = true

				local entity = Entity(node.info.entity)
				node.Icon:SetImage(getModelNodeIconPath(entity, entity:GetModel(), newVal))
				setModelClient(tree)
			end
			table.insert(editors, skinSlider)
		end

		---@type BodyGroupData[]
		local modelBodygroupData = csModel:GetBodyGroups()
		for i = 1, #modelBodygroupData do
			local bodygroupData = modelBodygroupData[i]
			if bodygroupData.num <= 1 then
				continue
			end

			local bodygroupSlider =
				category:NumSlider(string.NiceName(bodygroupData.name), "", 0, bodygroupData.num - 1, 0)
			---@cast bodygroupSlider DNumSlider
			bodygroupSlider:SetValue(tree.bodygroups[bodygroupData.id + 1])
			function bodygroupSlider:OnValueChanged(newVal)
				newVal = math.modf(newVal)
				shouldSet = true

				tree.bodygroups = string.SetChar(tree.bodygroups, bodygroupData.id + 1, tostring(newVal))
				setModelClient(tree)
			end
			table.insert(editors, bodygroupSlider)
		end
		csModel:Remove()

		return editors
	end

	local settingModelEntry = false

	function modelEntry:OnValueChange(newVal)
		-- In case we are requesting a model change
		if settingModelEntry then
			return
		end
		local node = treePanel:GetSelectedItem()

		net.Start("modeltree_modelrequest")
		net.WriteString(newVal)
		net.WriteString(node.info.model)
		net.SendToServer()
		settingModelEntry = true
	end

	---@param node ModelTreePanel_Node
	function treePanel:OnNodeSelected(node)
		settingModelEntry = true

		modelEntry:SetValue(node.info.model)
		panelState.haloedEntity = Entity(node.info.entity)
		dermaEditors = resetModelSettings(dermaEditors, modelForm, node.info)

		refreshTree(node.info)

		settingModelEntry = false
	end

	-- Initialize with our selection
	if IsValid(treePanel) and IsValid(treePanel.ancestor) then
		treePanel:SetSelectedItem(treePanel.ancestor)
		refreshTree(panelState.modelTree)
	end

	---If we are moving a `DNumSlider`, we are editing.
	---@param editors Panel[]|DNumSlider[]
	---@return boolean
	local function checkEditing(editors)
		for _, editor in ipairs(editors) do
			if editor:IsEditing() then
				return true
			end
		end
		return false
	end

	net.Receive("modeltree_modelresponse", function()
		local success = net.ReadBool()
		local model = net.ReadString()
		modelEntry:SetValue(model)

		if success then
			local node = treePanel:GetSelectedItem()
			node.info.model = model
			dermaEditors = resetModelSettings(dermaEditors, modelForm, node.info)
			node.Icon:SetImage(getModelNodeIconPath(Entity(node.info.entity), model, 0))
			shouldSet = true
		end

		settingModelEntry = false
	end)

	local lastThink = CurTime()
	local lastModelChange = -1
	timer.Remove("modeltree_think")
	if not IsValid(modelEntity) then
		return
	end

	timer.Create("modeltree_think", 0, -1, function()
		local now = CurTime()
		local editing = checkEditing(dermaEditors)
		if now - lastThink > 0.1 and shouldSet and not editing then
			syncTree(panelState.modelTree)
			lastThink = now
			shouldSet = false
		end

		-- Whether we should receive updates from the server or not.
		-- Useful if we want an external source to modify the model tree of the entity
		if lock:GetChecked() then
			return
		end

		if editing then
			return
		end

		if not IsValid(modelEntity) then
			return
		end

		if modelEntity.LastModelChange and modelEntity.LastModelChange ~= lastModelChange then
			refreshTree(panelState.modelTree)
			lastModelChange = modelEntity.LastModelChange
		end
	end)
	timer.Start("modeltree_think")
end

return ui
