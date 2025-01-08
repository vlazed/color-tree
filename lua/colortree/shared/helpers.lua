local helpers = {}

local ENTITY_FILTER = {
	proxyent_tf2itempaint = true,
	proxyent_tf2critglow = true,
	proxyent_tf2cloakeffect = true,
}

local MODEL_FILTER = {
	["models/error.mdl"] = true,
}

---Get a nicely formatted model name
---@param entity Entity
---@return string
function helpers.getModelNameNice(entity)
	local mdl = string.Split(entity:GetModel() or "", "/")
	mdl = mdl[#mdl]
	return string.NiceName(string.sub(mdl, 1, #mdl - 4))
end

---Get the model name without the path
---@param entity Entity
---@return string
function helpers.getModelName(entity)
	local mdl = string.Split(entity:GetModel(), "/")
	mdl = mdl[#mdl]
	return mdl
end

local modelSkins = {}

---Grab the entity's model icon
---@source https://github.com/NO-LOAFING/AdvBonemerge/blob/371b790d00d9bcbb62845ce8785fc6b98fbe8ef4/lua/weapons/gmod_tool/stools/advbonemerge.lua#L1079
---@param ent Entity
---@param model Model?
---@param skin Skin?
---@return string iconPath
function helpers.getModelNodeIconPath(ent, model, skin)
	skin = skin or ent:GetSkin() or 0
	model = model or ent:GetModel()

	if modelSkins[model .. skin] then
		return modelSkins[model .. skin]
	end

	local modelicon = "spawnicons/" .. string.StripExtension(model) .. ".png"
	local fallback = file.Exists("materials/" .. modelicon, "GAME") and modelicon or "icon16/bricks.png"
	if skin > 0 then
		modelicon = "spawnicons/" .. string.StripExtension(model) .. "_skin" .. skin .. ".png"
	end

	if not file.Exists("materials/" .. modelicon, "GAME") then
		modelicon = fallback
	else
		modelSkins[model .. skin] = modelicon
	end

	return modelicon
end

---Get a filtered array of the entity's children
---@param entity Entity
---@return Entity[]
function helpers.getValidModelChildren(entity)
	local filteredChildren = {}
	for i, child in ipairs(entity:GetChildren()) do
		if
			child.GetModel
			and child:GetModel()
			and not IsUselessModel(child:GetModel())
			and not MODEL_FILTER[child:GetModel()]
			and not ENTITY_FILTER[child:GetClass()]
		then
			table.insert(filteredChildren, child)
		end
	end
	return filteredChildren
end

---@param entity Entity
---@return Entity
function helpers.getAncestor(entity)
	while entity:GetParent() ~= NULL do
		entity = entity:GetParent()
	end
	return entity
end

---@param tbl table
---@return string
function helpers.encodeData(tbl)
	return util.Compress(util.TableToJSON(tbl))
end

---@param data string
---@return table
function helpers.decodeData(data)
	return util.JSONToTable(util.Decompress(data))
end

---@param ent Colorable|Entity
---@return boolean
function helpers.isAdvancedColorsInstalled(ent)
	return isfunction(ent.SetSubColor)
end

return helpers
