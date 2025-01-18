---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local getValidModelChildren, encodeData = helpers.getValidModelChildren, helpers.encodeData
local getModelName, getModelNameNice, getModelNodeIconPath =
	helpers.getModelName, helpers.getModelNameNice, helpers.getModelNodeIconPath

local ui = {}

---Update the entity's appearance in the client.
---This happens every tick on the client as opposed to the server, to optimize on the outgoing net rate.
---@param tree MaterialTree
local function setMaterialClient(tree)
	local entity = Entity(tree.entity)
	if not IsValid(entity) then
		return
	end

	entity:SetMaterial(tree.material)
	for ind, submaterial in pairs(tree.submaterials) do
		entity:SetSubMaterial(ind, submaterial)
	end

	if not tree.children and #tree.children == 0 then
		return
	end
	for _, child in ipairs(tree.children) do
		setMaterialClient(child)
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

---@param entity Entity
---@return string[]
local function getSubMaterials(entity)
	local submaterials = {}
	for ind, _ in ipairs(entity:GetMaterials()) do
		local submaterial = entity:GetSubMaterial(ind - 1)
		if submaterial and #submaterial ~= 0 and submaterial ~= "nil" then
			submaterials[ind - 1] = submaterial
		end
	end

	return submaterials
end

---Reset the materials of a (sub)tree
---@param tree MaterialTree
local function resetTree(tree)
	tree.material = ""
	tree.submaterials = {}
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		resetTree(child)
	end
end

---Send the entity material tree to the server
---@param tree MaterialTree
local function syncTree(tree)
	local data = encodeData(tree)
	net.Start("materialtree_sync", true)
	net.WriteUInt(#data, 17)
	net.WriteData(data)
	net.SendToServer()
end

---Get changes to the entity's material tree from an external source
---@param tree MaterialTree
local function refreshTree(tree)
	local entity = tree.entity and Entity(tree.entity) or NULL
	tree.material = IsValid(entity) and entity:GetMaterial() or ""
	for ind, _ in ipairs(entity:GetMaterials()) do
		local submaterial = entity:GetSubMaterial(ind - 1)
		if submaterial and #submaterial ~= 0 and submaterial ~= "nil" then
			tree.submaterials[ind - 1] = submaterial
		else
			tree.submaterials[ind - 1] = nil
		end
	end
	if not tree.children or #tree.children == 0 then
		return
	end

	for _, child in ipairs(tree.children) do
		refreshTree(child)
	end
end

---Add hooks and material tree pointers
---@param parent MaterialTreePanel_Node
---@param entity Entity
---@param info MaterialTree
---@param rootInfo MaterialTree
---@return MaterialTreePanel_Node
local function addNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node MaterialTreePanel_Node

	node:SetExpanded(true, true)

	function node:DoRightClick()
		if not IsValid(entity) then
			return
		end

		local menu = DermaMenu()
		menu:AddOption("Reset Material", function()
			resetTree(info)
			syncTree(rootInfo)
		end)

		menu:Open()
	end

	node.Icon:SetImage(getModelNodeIconPath(entity))
	node.info = info

	return node
end

---Construct the material tree
---@param parent Entity
---@return MaterialTree
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

			---@type MaterialTree
			local node = {
				parent = parent:EntIndex(),
				route = route,
				entity = child:EntIndex(),
				material = child:GetMaterial(),
				submaterials = getSubMaterials(child),
				children = entityHierarchy(child, route),
			}
			table.insert(tree, node)
			route = {}
		end
	end

	return tree
end

---Construct the DTree from the entity material tree
---@param tree MaterialTree
---@param nodeParent MaterialTreePanel_Node
---@param root MaterialTree
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

---Construct the `entity`'s material tree
---@param treePanel MaterialTreePanel
---@param entity Entity
---@returns MaterialTree
local function buildTree(treePanel, entity)
	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:Remove()
	end

	---@type MaterialTree
	local hierarchy = {
		entity = entity:EntIndex(),
		material = entity:GetMaterial(),
		submaterials = getSubMaterials(entity),
		children = entityHierarchy(entity, {}),
	}

	---@type MaterialTreePanel_Node
	---@diagnostic disable-next-line
	treePanel.ancestor = addNode(treePanel, entity, hierarchy, hierarchy)
	treePanel.ancestor.Icon:SetImage(getModelNodeIconPath(entity))
	treePanel.ancestor.info = hierarchy
	hierarchyPanel(hierarchy.children, treePanel.ancestor, hierarchy)

	return hierarchy
end

---@type colortree_submaterials
local submaterialFrame = nil
local settingMaterialEntry = false

---Set the entity for the submaterial frame.
---
---~~VENT:~~
---
---~~the cringiest thing to exist 🤮🤮🤮, because panels don't update immediately for some reason (need to move the divider to see it happen)
---so we force it with the worst thing possible: recreating the vgui 🤢~~
---@param entity Entity
---@param submaterials table?
---@param panelChildren MaterialPanelChildren
---@param panelState MaterialPanelState
local function setSubMaterialEntity(entity, submaterials, panelChildren, panelState)
	local lastVisible = false
	if IsValid(submaterialFrame) then
		lastVisible = submaterialFrame:IsVisible()
		submaterialFrame:Remove()
	end

	submaterialFrame = vgui.Create("colortree_submaterials")
	submaterialFrame:SetHelp("#tool.materialtree.submaterial.help")
	submaterialFrame:SetVisible(lastVisible)
	submaterialFrame:SetEntity(entity)
	if submaterials then
		submaterialFrame:SetSubMaterials(submaterials)
	end

	-- We'll hook the submaterial frame here for the time being
	if submaterialFrame and IsValid(submaterialFrame) then
		function submaterialFrame:OnSelectedMaterial(id)
			local node = panelChildren.treePanel:GetSelectedItem()

			settingMaterialEntry = true
			panelChildren.materialEntry:SetValue(node.info.submaterials[id] or "")
			settingMaterialEntry = false
		end

		function submaterialFrame:OnRemovedSubMaterial(id)
			local node = panelChildren.treePanel:GetSelectedItem()
			node.info.submaterials[id] = nil
			syncTree(panelState.materialTree)
		end

		function submaterialFrame:OnClearSelection()
			local node = panelChildren.treePanel:GetSelectedItem()
			node.info.submaterials = {}
			syncTree(panelState.materialTree)
		end
	end
end

---@param cPanel DForm|ControlPanel
---@param panelProps MaterialPanelProps
---@param panelState MaterialPanelState
---@return MaterialPanelChildren
function ui.ConstructPanel(cPanel, panelProps, panelState)
	local materialEntity = panelProps.materialEntity

	local treeForm = makeCategory(cPanel, "Entity Hierarchy", "DForm")
	treeForm:Help(
		IsValid(materialEntity) and "Entity hierarchy for " .. getModelName(materialEntity) or "No entity selected"
	)
	local treePanel = vgui.Create("DTree", treeForm)
	---@cast treePanel MaterialTreePanel
	if IsValid(materialEntity) then
		panelState.materialTree = buildTree(treePanel, materialEntity)
	else
		panelState.haloedEntity = NULL
		panelState.materialTree = {} ---@diagnostic disable-line
	end
	treeForm:AddItem(treePanel)
	treePanel:Dock(TOP)
	treePanel:SetSize(treeForm:GetWide(), 250)

	local materialForm = makeCategory(cPanel, "Material", "ControlPanel")
	materialForm:Help("#tool.materialtree.material")
	local materialClear = vgui.Create("DButton", materialForm)
	local materialEntry = vgui.Create("DTextEntry", materialForm)
	---@cast materialEntry DTextEntry
	materialForm:AddItem(materialEntry, materialClear)
	materialEntry:Dock(FILL)

	materialClear:SetText("X")
	materialClear:SetTooltip("#tool.materialtree.clear.tooltip")
	materialClear:Dock(RIGHT)

	if IsValid(materialEntity) then
		materialEntry:SetText(materialEntity:GetMaterial())
	end

	---@source https://github.com/Facepunch/garrysmod/blob/e47ac049d026f922867ee3adb2c4746fb1244300/garrysmod/gamemodes/sandbox/entities/weapons/gmod_tool/stools/material.lua#L136
	---START SOURCE
	-- Remove duplicate materials. table.HasValue is used to preserve material order
	local materials = {}
	for id, str in ipairs( list.Get( "OverrideMaterials" ) ) do
		if ( !table.HasValue( materials, str ) ) then
			table.insert( materials, str )
		end
	end

	local materialGallery = materialForm:MatSelect( "material_override", materials, true, 0.25, 0.25 )
	---END SOURCE

	local settings = makeCategory(cPanel, "Settings", "DForm")
	local propagate = settings:CheckBox("#tool.materialtree.propagate", "materialtree_propagate")
	propagate:SetTooltip("#tool.materialtree.propagate.tooltip")

	---@type DCheckBoxLabel
	---@diagnostic disable-next-line
	local lock = settings:CheckBox("#tool.materialtree.lock", "materialtree_lock")
	lock:SetTooltip("#tool.materialtree.lock.tooltip")

	if IsValid(submaterialFrame) then
		submaterialFrame:Remove()
	end

	return {
		treePanel = treePanel,
		materialForm = materialForm,
		materialEntry = materialEntry,
		materialClear = materialClear,
		materialGallery = materialGallery,
		propagate = propagate,
		lock = lock,
	}
end

---@param panelChildren MaterialPanelChildren
---@param panelProps MaterialPanelProps
---@param panelState MaterialPanelState
function ui.HookPanel(panelChildren, panelProps, panelState)
	local materialEntity = panelProps.materialEntity

	local treePanel = panelChildren.treePanel
	local materialForm = panelChildren.materialForm
	local materialEntry = panelChildren.materialEntry
	local materialClear = panelChildren.materialClear
	local materialGallery = panelChildren.materialGallery
	local propagate = panelChildren.propagate
	local lock = panelChildren.lock

	local shouldSet = false

	function materialGallery:OnSelect(material)
		materialEntry:SetValue(material)
	end

	function materialClear:DoClick()
		materialEntry:SetValue("")
	end

	---@param tree MaterialTree
	local function setMaterial(tree, newMaterial)
		tree.material = newMaterial

		if not propagate:GetChecked() then return end
		if not tree.children or #tree.children == 0 then return end
		
		for _, child in ipairs(tree.children) do
			setMaterial(child, newMaterial)
		end
	end

	function materialEntry:OnValueChange(newVal)
		-- In case we are requesting a material change
		if settingMaterialEntry then
			return
		end
		local node = treePanel:GetSelectedItem()
		local submaterials = submaterialFrame:GetSelectedSubMaterials()
		if #submaterials > 0 then
			for _, id in ipairs(submaterials) do
				node.info.submaterials[id] = newVal
			end
		else
			setMaterial(node.info, newVal)
		end
		-- setMaterialClient(node.info)
		shouldSet = true
	end

	---@param node MaterialTreePanel_Node
	function treePanel:OnNodeSelected(node)
		local entity = Entity(node.info.entity)
		settingMaterialEntry = true

		setSubMaterialEntity(entity, table.GetKeys(node.info.submaterials), panelChildren, panelState)
		materialEntry:SetValue(node.info.material)
		panelState.haloedEntity = Entity(node.info.entity)

		refreshTree(node.info)

		settingMaterialEntry = false
	end

	-- Initialize with our selection
	if IsValid(treePanel) and IsValid(treePanel.ancestor) then
		treePanel:SetSelectedItem(treePanel.ancestor)
		setSubMaterialEntity(materialEntity, table.GetKeys(getSubMaterials(materialEntity)), panelChildren, panelState)
		refreshTree(panelState.materialTree)
	end

	hook.Remove("OnContextMenuOpen", "materialtree_hookcontext")
	if IsValid(submaterialFrame) then
		hook.Add("OnContextMenuOpen", "materialtree_hookcontext", function()
			local tool = LocalPlayer():GetTool()
			if tool and tool.Mode == "materialtree" then
				submaterialFrame:SetVisible(true)
				submaterialFrame:MakePopup()
			end
		end)
	end

	hook.Remove("OnContextMenuClose", "materialtree_hookcontext")
	if IsValid(submaterialFrame) then
		hook.Add("OnContextMenuClose", "materialtree_hookcontext", function()
			submaterialFrame:SetVisible(false)
			submaterialFrame:SetMouseInputEnabled(false)
			submaterialFrame:SetKeyboardInputEnabled(false)
		end)
	end

	---@return boolean
	local function checkEditing()
		return materialEntry:HasFocus()
	end

	local lastThink = CurTime()
	local lastMaterialChange = -1
	timer.Remove("materialtree_think")
	timer.Create("materialtree_think", 0, -1, function()
		local now = CurTime()
		local editing = checkEditing()
		if now - lastThink > 0.1 and shouldSet and not editing then
			syncTree(panelState.materialTree)
			lastThink = now
			shouldSet = false
		end

		-- Whether we should receive updates from the server or not.
		-- Useful if we want an external source to modify the material tree of the entity
		if lock:GetChecked() then
			return
		end

		if editing then
			return
		end

		if not IsValid(materialEntity) then
			return
		end

		if materialEntity.LastMaterialChange and materialEntity.LastMaterialChange ~= lastMaterialChange then
			refreshTree(panelState.materialTree)
			lastMaterialChange = materialEntity.LastMaterialChange
		end
	end)
	timer.Start("materialtree_think")
end

return ui
