TOOL.Category = "Render"
TOOL.Name = "#tool.modeltree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["lock"] = 0
TOOL.ClientConVar["propagate"] = 0

local CHANGE_BITS = 7
local TIME_PRECISION = 10

---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local decodeData, getAncestor = helpers.decodeData, helpers.getAncestor

do -- Keep track of the last time the skin, bodygroups, or model of an entity or its children has changed
	---@class ModelEntity
	local meta = FindMetaTable("Entity")
	if meta.modeltree_oldSetModel == nil then
		meta.modeltree_oldSetModel = meta.SetModel
	end
	if meta.modeltree_oldSetBodyGroups == nil then
		meta.modeltree_oldSetBodyGroups = meta.SetBodyGroups
	end
	if meta.modeltree_oldSetSkin == nil then
		meta.modeltree_oldSetSkin = meta.SetSkin
	end

	---Propagate the changed model event to the ancestral entity
	---@param entity Entity
	local function updateModel(entity)
		net.Start("modeltree_update", true)
		net.WriteEntity(entity)
		net.WriteUInt(CurTime() * TIME_PRECISION, CHANGE_BITS)
		net.Broadcast()
	end

	function meta:SetModel(newModel, ...)
		if not newModel then
			return self:modeltree_oldSetModel(newModel, ...)
		end

		local root = getAncestor(self)

		if SERVER then
			updateModel(root)
		end

		return self:modeltree_oldSetModel(newModel, ...)
	end

	function meta:SetBodyGroups(newBodygroups, ...)
		if not newBodygroups then
			return self:modeltree_oldSetBodyGroups(newBodygroups, ...)
		end

		local root = getAncestor(self)

		if SERVER then
			updateModel(root)
		end

		return self:modeltree_oldSetBodyGroups(newBodygroups, ...)
	end

	function meta:SetSkin(newSkin, ...)
		if not newSkin then
			return self:modeltree_oldSetSkin(newSkin, ...)
		end

		local root = getAncestor(self)

		if SERVER then
			updateModel(root)
		end

		return self:modeltree_oldSetSkin(newSkin, ...)
	end
end

local lastModelEntity = NULL
local lastValidModel = false
function TOOL:Think()
	local currentModelEntity = self:GetModelEntity()
	local validModel = IsValid(currentModelEntity)

	if currentModelEntity == lastModelEntity and validModel == lastValidModel then
		return
	end

	if not validModel then
		self:SetOperation(0)
	else
		self:SetOperation(1)
	end

	if CLIENT then
		self:RebuildControlPanel(currentModelEntity)
	end
	lastModelEntity = currentModelEntity
	lastValidModel = validModel
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
	if IsValid(tr.Entity) then
		tr.Entity:CallOnRemove("modeltree_removeentity", function()
			if IsValid(self:GetWeapon()) then
				self:SetModelEntity(NULL)
			end
		end)
	end
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
		if ent:GetModel() ~= data.modeltree_model then
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
			modeltree_defaultskin = node.defaultSkin,
			modeltree_bodygroups = node.bodygroups,
			modeltree_defaultbodygroups = node.defaultBodygroups,
		}
	end

	---Recursively call `setModel` on the tree's descendants
	---@param modelTree ModelTree
	local function setModelWithTree(modelTree, ply)
		setModel(ply, Entity(modelTree.entity), getModelTreeData(modelTree))
		if not modelTree.children or #modelTree.children == 0 then
			return
		end

		for _, node in ipairs(modelTree.children) do
			setModelWithTree(node)
		end
	end

	duplicator.RegisterEntityModifier("modeltree", setModel)

	net.Receive("modeltree_modelrequest", function(len, ply)
		local newModel = net.ReadString()
		local oldModel = net.ReadString()
		local setModel = ""
		local success = false

		if IsUselessModel(newModel) or not util.IsValidModel(newModel) then
			setModel = oldModel
		else
			setModel = newModel
			success = true
		end

		net.Start("modeltree_modelresponse")
		net.WriteBool(success)
		net.WriteString(setModel)
		net.Send(ply)
	end)

	net.Receive("modeltree_sync", function(len, ply)
		local treeLen = net.ReadUInt(17)
		local encodedTree = net.ReadData(treeLen)
		local tree = decodeData(encodedTree)

		setModelWithTree(tree, ply)
	end)

	return
else
	net.Receive("modeltree_update", function(_, _)
		local entity = net.ReadEntity()
		entity.LastModelChange = net.ReadUInt(CHANGE_BITS)
	end)
end

---@module "colortree.client.modelui"
local ui = include("colortree/client/modelui.lua")

---@type ModelPanelState
local panelState = {
	haloedEntity = NULL,
	haloColor = color_white,
}

---@param cPanel ControlPanel|DForm
---@param modelEntity ModelEntity
function TOOL.BuildCPanel(cPanel, modelEntity)
	local panelChildren = ui.ConstructPanel(cPanel, { modelEntity = modelEntity }, panelState)
	ui.HookPanel(panelChildren, { modelEntity = modelEntity }, panelState)
end

local TOOL = TOOL
local player = LocalPlayer()
hook.Remove("PreDrawHalos", "modeltree_halos")
hook.Add("PreDrawHalos", "modeltree_halos", function()
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
