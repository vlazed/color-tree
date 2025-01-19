TOOL.Category = "Render"
TOOL.Name = "#tool.materialtree.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["lock"] = 0
TOOL.ClientConVar["propagate"] = 0

local CHANGE_BITS = 7
local TIME_PRECISION = 10

---@module "colortree.shared.helpers"
local helpers = include("colortree/shared/helpers.lua")

local decodeData, getAncestor = helpers.decodeData, helpers.getAncestor

do -- Keep track of the last time the materials of an entity or its children has changed
	---@class MaterialEntity
	local meta = FindMetaTable("Entity")
	if meta.materialtree_oldSetMaterial == nil then
		meta.materialtree_oldSetMaterial = meta.SetMaterial
	end
	if meta.materialtree_oldSetSubMaterial == nil then
		meta.materialtree_oldSetSubMaterial = meta.SetSubMaterial
	end

	---Propagate the changed material event to the ancestral entity
	---@param entity Entity
	local function updateMaterial(entity)
		net.Start("materialtree_update", true)
		net.WriteEntity(entity)
		net.WriteUInt(CurTime() * TIME_PRECISION, CHANGE_BITS)
		net.Broadcast()
	end

	function meta:SetMaterial(newMaterial, ...)
		if not newMaterial then
			return self:materialtree_oldSetMaterial(newMaterial, ...)
		end

		local root = getAncestor(self)

		if SERVER then
			updateMaterial(root)
		end

		return self:materialtree_oldSetMaterial(newMaterial, ...)
	end

	function meta:SetSubMaterial(index, newSubMaterial, ...)
		local now = CurTime()
		meta.LastMaterialChange = meta.LastMaterialChange or now
		local root = getAncestor(self)

		if SERVER and meta.LastMaterialChange ~= now then
			updateMaterial(root)
		end

		meta.LastMaterialChange = now
		return self:materialtree_oldSetSubMaterial(index, newSubMaterial, ...)
	end
end

local lastMaterialEntity = NULL
local lastValidMaterial = false
function TOOL:Think()
	local currentMaterialEntity = self:GetMaterialEntity()
	local validMaterial = IsValid(currentMaterialEntity)

	if currentMaterialEntity == lastMaterialEntity and validMaterial == lastValidMaterial then
		return
	end

	if not validMaterial then
		self:SetOperation(0)
	else
		self:SetOperation(1)
	end

	if CLIENT then
		self:RebuildControlPanel(currentMaterialEntity)
	end
	lastMaterialEntity = currentMaterialEntity
	lastValidMaterial = validMaterial
end

---@param newMaterialEntity Entity
function TOOL:SetMaterialEntity(newMaterialEntity)
	self:GetWeapon():SetNW2Entity("materialtree_entity", newMaterialEntity)
end

---@return Entity MaterialEntity
function TOOL:GetMaterialEntity()
	return self:GetWeapon():GetNW2Entity("materialtree_entity")
end

---Select the entity to manipulate its entity material tree
---@param tr table|TraceResult
---@return boolean
function TOOL:RightClick(tr)
	self:SetMaterialEntity(IsValid(tr.Entity) and tr.Entity or NULL)
	if IsValid(tr.Entity) then
		tr.Entity:CallOnRemove("materialtree_removeentity", function()
			if IsValid(self:GetWeapon()) then
				self:SetMaterialEntity(NULL)
			end
		end)
	end
	return true
end

if SERVER then
	---Set the materials of the entity
	---@param ply Player
	---@param ent Entity
	---@param data MaterialTreeData
	local function setMaterial(ply, ent, data)
		if IsValid(ply) then
			ent.materialtree_owner = ply
		end

		ent:SetMaterial(data.materialtree_material)
		---Some tools like Advanced Colour Tool detour the SetSubMaterial function to send some values.
		---Naively, if we don't check if our materials are different, then we would be setting these for
		---ALL submaterials, which results in unnecessary net calls which lags the client.
		for ind, _ in ipairs(ent:GetMaterials()) do
			local submaterial = data.materialtree_submaterials[ind - 1]
			if ent:GetSubMaterial(ind - 1) ~= tostring(submaterial) then
				ent:SetSubMaterial(ind - 1, Either(submaterial and submaterial ~= "nil", submaterial, ""))
			end
		end

		duplicator.StoreEntityModifier(ent, "materialtree", data)
	end

	---Transform an entity's material tree into data saved for duping
	---@param node MaterialTree
	---@returns MaterialTreeData
	local function getMaterialTreeData(node)
		return {
			materialtree_material = node.material,
			materialtree_submaterials = node.submaterials,
		}
	end

	---Recursively call `setMaterial` on the tree's descendants
	---@param materialTree MaterialTree
	local function setMaterialWithTree(materialTree, ply)
		setMaterial(ply, Entity(materialTree.entity), getMaterialTreeData(materialTree))

		if not materialTree.children or #materialTree.children == 0 then
			return
		end

		for _, node in ipairs(materialTree.children) do
			setMaterialWithTree(node)
		end
	end

	duplicator.RegisterEntityModifier("materialtree", setMaterial)

	net.Receive("materialtree_sync", function(len, ply)
		local treeLen = net.ReadUInt(17)
		local encodedTree = net.ReadData(treeLen)
		local tree = decodeData(encodedTree)

		setMaterialWithTree(tree, ply)
	end)

	return
else
	net.Receive("materialtree_update", function(_, _)
		local entity = net.ReadEntity()
		entity.LastMaterialChange = net.ReadUInt(CHANGE_BITS)
	end)
end

---@module "colortree.client.materialui"
local ui = include("colortree/client/materialui.lua")

---@type MaterialPanelState
local panelState = {
	haloedEntity = NULL,
	haloColor = color_white,
}

---@param cPanel ControlPanel|DForm
---@param materialEntity MaterialEntity
function TOOL.BuildCPanel(cPanel, materialEntity)
	local panelChildren = ui.ConstructPanel(cPanel, { materialEntity = materialEntity }, panelState)
	ui.HookPanel(panelChildren, { materialEntity = materialEntity }, panelState)
end

local TOOL = TOOL
local player = LocalPlayer()
hook.Remove("PreDrawHalos", "materialtree_halos")
hook.Add("PreDrawHalos", "materialtree_halos", function()
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
