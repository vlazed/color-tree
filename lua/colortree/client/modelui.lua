---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local getValidModelChildren, encodeData = helpers.getValidModelChildren, helpers.encodeData

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
	for i = 0, ent:GetNumBodyGroups() do
		bodygroups = bodygroups .. tostring(ent:GetBodygroup(i))
	end
	return bodygroups
end

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

local skins = {}

---Grab the entity's model icon
---@source https://github.com/NO-LOAFING/AdvBonemerge/blob/371b790d00d9bcbb62845ce8785fc6b98fbe8ef4/lua/weapons/gmod_tool/stools/advbonemerge.lua#L1079
---@param ent Entity
---@param model Model?
---@param skin Skin?
---@return string iconPath
local function getModelNodeIconPath(ent, model, skin)
	skin = skin or ent:GetSkin() or 0
	model = model or ent:GetModel()

	if skins[model .. skin] then
		return skins[model .. skin]
	end

	local modelicon = "spawnicons/" .. string.StripExtension(model) .. ".png"
	local fallback = file.Exists("materials/" .. modelicon, "GAME") and modelicon or "icon16/bricks.png"
	if skin > 0 then
		modelicon = "spawnicons/" .. string.StripExtension(model) .. "_skin" .. skin .. ".png"
	end

	if not file.Exists("materials/" .. modelicon, "GAME") then
		modelicon = fallback
	else
		skins[model .. skin] = modelicon
	end

	return modelicon
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

---Add hooks and model tree pointers
---@param parent ModelTreePanel_Node
---@param entity Entity
---@param info ModelTree
---@param rootInfo ModelTree
---@return ModelTreePanel_Node
local function addNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node ModelTreePanel_Node

	function node:DoRightClick()
		if not IsValid(entity) then
			return
		end

		local menu = DermaMenu()
		menu:AddOption("Reset Model", function()
			resetTree(info)
			syncTree(rootInfo)
		end)

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
			---@type ModelTree
			local node = {
				parent = parent:EntIndex(),
				route = route,
				entity = child:EntIndex(),
				model = child:GetModel(),
				defaultModel = child:GetModel(),
				defaultSkin = child:GetSkin(),
				defaultBodygroups = getBodygroups(child),
				children = entityHierarchy(child, route),
				skin = child:GetRenderFX(),
				bodygroups = getBodygroups(child),
				bodygroupData = child:GetBodyGroups(),
			}
			table.insert(tree, node)
			route = {}
		end
	end

	return tree
end

---Construct a flat array of the entity's models from the model tree
---@param entity Entity
---@param tbl any
---@return any
local function getModelChildrenIdentifier(entity, tbl)
	if not IsValid(entity) then
		return {}
	end

	local children = getValidModelChildren(entity)
	for _, child in ipairs(children) do
		table.insert(tbl, child:GetModel())
		table.insert(tbl, child:GetSkin())
		table.insert(tbl, getBodygroups(child))
		getModelChildrenIdentifier(child, tbl)
	end

	return tbl
end

---Check if every descendant's model is equal to some other descendant model
---@param t1 table
---@param t2 table
local function isModelChildrenEqual(t1, t2)
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
		bodygroupData = entity:GetBodyGroups(),
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

local PANEL_FILTER = {
	DCategoryHeader = true,
	DLabel = true,
	DTextEntry = true,
}

---@param cPanel DForm|ControlPanel
---@param panelProps ModelPanelProps
---@param panelState ModelPanelState
---@return table
function ui.ConstructPanel(cPanel, panelProps, panelState)
	local modelEntity = panelProps.modelEntity

	local treeForm = makeCategory(cPanel, "Entity Hierarchy", "DForm")
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

	return {
		treePanel = treePanel,
		modelForm = modelForm,
		modelEntry = modelEntry,
		lock = lock,
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

	local dermaEditors = {}
	local shouldSet = false

	---Change the settings when we select another model to edit
	---@param category DForm
	---@param tree ModelTree
	---@returns Panel[]
	local function resetModelSettings(category, tree)
		for _, panel in ipairs(category:GetChildren()) do
			if IsValid(panel) then
				if PANEL_FILTER[panel:GetName()] then
					continue
				end

				if panel:GetName() == "DSizeToContents" and PANEL_FILTER[panel:GetChildren()[1]:GetName()] then
					continue
				end

				panel:Remove()
			end
		end

		local entity = Entity(tree.entity)
		local editors = {}
		local skins = entity:SkinCount()
		if skins > 1 then
			local skinSlider = category:NumSlider("Skin", "", 0, skins - 1, 0)
			---@cast skinSlider DNumSlider
			skinSlider:SetValue(tree.skin)
			function skinSlider:OnValueChanged(newVal)
				local node = treePanel:GetSelectedItem()
				newVal = math.modf(newVal)

				tree.skin = newVal
				shouldSet = true

				local entity = Entity(node.info.entity)
				node.Icon:SetImage(getModelNodeIconPath(entity, entity:GetModel(), newVal))
				setModelClient(tree)
			end
			table.insert(editors, skinSlider)
		end

		for i = 2, #tree.bodygroupData do
			local bodygroupData = tree.bodygroupData[i]
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

		return editors
	end

	function modelEntry:OnValueChange(newVal)
		dermaEditors = resetModelSettings(modelForm, newVal)
		local node = treePanel:GetSelectedItem()
		node.Icon:SetImage(getModelNodeIconPath(Entity(node.info.entity), newVal, 0))
	end

	---@param node ColorTreePanel_Node
	function treePanel:OnNodeSelected(node)
		panelState.haloedEntity = Entity(node.info.entity)
		dermaEditors = resetModelSettings(modelForm, panelState.modelTree)
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

	local lastThink = CurTime()
	local lastModelChildren = {}
	timer.Remove("modeltree_think")
	timer.Create("modeltree_think", 0, -1, function()
		local now = CurTime()
		local editing = checkEditing(dermaEditors)
		if now - lastThink > 0.1 and shouldSet and not editing then
			syncTree(panelState.modelTree)
			lastThink = now
			shouldSet = false
		end

		-- Whether we should receive updates from the server or not.
		-- Useful if we want an external source to modify the models of the entity
		if lock:GetChecked() then
			return
		end

		local currentModelChildren = getModelChildrenIdentifier(modelEntity, {})

		if not isModelChildrenEqual(lastModelChildren, currentModelChildren) then
			refreshTree(panelState.modelTree)
			lastModelChildren = currentModelChildren
		end
	end)
	timer.Start("modeltree_think")
end

return ui
