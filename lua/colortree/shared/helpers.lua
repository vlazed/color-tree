local helpers = {}

local ENTITY_FILTER = {
	proxyent_tf2itempaint = true,
	proxyent_tf2critglow = true,
	proxyent_tf2cloakeffect = true,
}

local MODEL_FILTER = {
	["models/error.mdl"] = true,
}

---Get a filtered array of the entity's children
---@param entity Entity
---@return Entity[]
function helpers.getValidModelChildren(entity)
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
function helpers.encodeData(tbl)
	return util.Compress(util.TableToJSON(tbl))
end

---@param data string
---@return table
function helpers.decodeData(data)
	return util.JSONToTable(util.Decompress(data))
end

return helpers
