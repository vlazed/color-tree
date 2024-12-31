TOOL.Category = "Render"
TOOL.Name = "#tool.modeltree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["lock"] = 0

---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local decodeData = helpers.decodeData

local lastModelEntity = NULL
function TOOL:Think()
	local currentModelEntity = self:GetModelEntity()
	if currentModelEntity == NULL then
		self:SetOperation(0)
	else
		self:SetOperation(1)
	end

	if currentModelEntity == lastModelEntity then
		return
	end

	if CLIENT then
		self:RebuildControlPanel(currentModelEntity)
	end
	lastModelEntity = currentModelEntity
end

---@param newModelEntity Entity
function TOOL:SetModelEntity(newModelEntity)
	self:GetWeapon():SetNW2Entity("modeltree_entity", newModelEntity)
end

---@return Entity modelEntity
function TOOL:GetModelEntity()
	return self:GetWeapon():GetNW2Entity("modeltree_entity")
end

---Select the entity to manipulate its entity model tree
---@param tr table|TraceResult
---@return boolean
function TOOL:RightClick(tr)
	self:SetModelEntity(IsValid(tr.Entity) and tr.Entity or NULL)
	return true
end

if SERVER then
	---Set the models of the entity
	---@param ply Player
	---@param ent Entity
	---@param data ModelTreeData
	local function setModel(ply, ent, data)
		if IsValid(ply) then
			ent.modeltree_owner = ply
		end
		if ent:GetModel() ~= data.modeltree_defaultmodel then
			ent:SetModel(data.modeltree_model)
		end
		ent:SetSkin(data.modeltree_skin)
		ent:SetBodyGroups(data.modeltree_bodygroups)

		duplicator.StoreEntityModifier(ent, "modeltree", data)
	end

	---Transform an entity's model tree into data saved for duping
	---@param node ModelTree
	---@returns ModelTreeData
	local function getModelTreeData(node)
		return {
			modeltree_model = node.model,
			modeltree_defaultmodel = node.defaultModel,
			modeltree_skin = node.skin,
			modeltree_bodygroups = node.bodygroups,
		}
	end

	---Recursively call `setModel` on the tree's descendants
	---@param descendantTree ModelTree
	local function setModelWithTree(descendantTree, ply)
		if not descendantTree.children or #descendantTree.children == 0 then
			return
		end

		for _, node in ipairs(descendantTree.children) do
			setModel(ply, Entity(node.entity), getModelTreeData(node))
			if node.children and #node.children > 0 then
				setModelWithTree(node.children)
			end
		end
	end

	duplicator.RegisterEntityModifier("modeltree", setModel)

	net.Receive("modeltree_sync", function(len, ply)
		local treeLen = net.ReadUInt(17)
		local encodedTree = net.ReadData(treeLen)
		local tree = decodeData(encodedTree)

		setModel(ply, Entity(tree.entity), getModelTreeData(tree))
		setModelWithTree(tree, ply)
	end)

	return
end

---@module "colortree.client.modelui"
local ui = include("colortree/client/modelui.lua")

---@type ModelPanelState
local panelState = {
	haloedEntity = NULL,
	haloColor = color_white,
}

---@param cPanel ControlPanel|DForm
---@param modelEntity Entity
function TOOL.BuildCPanel(cPanel, modelEntity)
	local panelChildren = ui.ConstructPanel(cPanel, { modelEntity = modelEntity }, panelState)
	ui.HookPanel(panelChildren, { modelEntity = modelEntity }, panelState)
end

hook.Remove("PreDrawHalos", "modeltree_halos")
hook.Add("PreDrawHalos", "modeltree_halos", function()
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
