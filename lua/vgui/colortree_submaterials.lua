---@class colortree_selection: DPanel
---@field PreviewIcon DImage
---@field MaterialList DListView
---@field ClearButton DButton

---@class colortree_submaterials: DFrame
---@field Selection colortree_selection
local PANEL = {}

local WIDTH, HEIGHT = ScrW(), ScrH()

local BACKUP_MATERIAL = Material("null")
local materialsMap = {}
local aspectRatios = {}

---@param material IMaterial
local function getAspectRatio(material)
	local name = material:GetName()
	if aspectRatios[name] then
		return aspectRatios[name]
	end

	aspectRatios[name] = material:Width() / material:Height()
	return aspectRatios[name]
end

---@param materialPath string
---@return IMaterial
local function getMaterial(materialPath)
	if materialsMap[materialPath] then
		return materialsMap[materialPath]
	end

	materialsMap[materialPath] = Material(materialPath)
	return materialsMap[materialPath]
end

---@param path string
---@return string
local function shortPath(path)
	local split = string.Split(path, "/")
	return split[#split]
end

function PANEL:Init()
	self:SetTitle("Submaterial Gallery")

	self:SetDraggable(false)
	self:ShowCloseButton(false)
	self:SetDeleteOnClose(false)
	self:SetSizable(false)

	self:SetPos(WIDTH * 0.1, HEIGHT * 0.25)
	self:SetSize(WIDTH * 0.25, HEIGHT * 0.5)

	self.ButtonHeight = 80

	self.Divider = vgui.Create("DHorizontalDivider", self)

	---@type colortree_selection
	---@diagnostic disable-next-line
	self.Selection = vgui.Create("DPanel", self)
	self.Selection.PreviewIcon = vgui.Create("DImage", self.Selection)

	self.Selection.MaterialList = vgui.Create("DListView", self.Selection)
	self.Selection.MaterialList:AddColumn("Selected")
	self.Selection.MaterialList:SetMultiSelect(false)

	self.Selection.ClearButton = vgui.Create("DButton", self.Selection)
	self.Selection.ClearButton:SetText("Clear All")
	function self.Selection.ClearButton.DoClick()
		self:ClearSelection()
	end

	self.Gallery = vgui.Create("DPanel", self)
	self.Gallery.Scroll = vgui.Create("DScrollPanel", self.Gallery)
	self.Gallery.Grid = vgui.Create("DIconLayout", self.Gallery.Scroll)

	self.Divider:SetLeft(self.Selection)
	self.Divider:SetRight(self.Gallery)

	self.Tooltip = vgui.Create("DLabel")
	self.Tooltip:SetVisible(false)
	self.Tooltip:SetWrap(true)
	self.Tooltip:SetDrawOnTop(true)
	self.Tooltip:SetSize(200, 200)
	self.Tooltip:SetFont("DefaultFixedDropShadow")

	self.Entity = NULL

	self.submaterials = {}
	self.submaterialSet = {}
end

function PANEL:Paint(w, h)
	local old = DisableClipping(true)
	DisableClipping(old)

	derma.SkinHook("Paint", "Frame", self, w, h)
	return true
end

function PANEL:PerformLayout(width, height)
	---@diagnostic disable-next-line
	self.BaseClass.PerformLayout(self, width, height)

	self.Divider:Dock(FILL)

	self.Selection:Dock(LEFT)
	self.Gallery:Dock(RIGHT)
	self.Gallery.Scroll:Dock(FILL)
	self.Gallery.Grid:Dock(FILL)

	self.Selection.PreviewIcon:Dock(TOP)
	self.Selection.MaterialList:Dock(FILL)
	self.Selection.ClearButton:Dock(BOTTOM)

	self.Selection.PreviewIcon:SetTall(self.Selection.PreviewIcon:GetWide())
end

function PANEL:GetSubMaterials()
	return self.submaterials
end

function PANEL:TransformSubMaterials(submaterialIds)
	local transformed = {}
	local materials = self.Entity:GetMaterials()
	for _, submaterialId in pairs(submaterialIds) do
		local submaterial = materials[submaterialId + 1]
		self.submaterialSet[submaterialId] =
			table.insert(transformed, { submaterialId, shortPath(submaterial), getMaterial(submaterial) })
	end
	return transformed
end

function PANEL:SetSubMaterials(submaterials)
	self.submaterials = self:TransformSubMaterials(submaterials)
	self:RefreshSelection()
end

function PANEL:RefreshSubMaterialSet()
	for i, submaterialStruct in ipairs(self.submaterials) do
		self.submaterialSet[submaterialStruct[1]] = i
	end
end

function PANEL:ClearSelection()
	self.submaterials = {}
	self.submaterialSet = {}
	self.Selection.PreviewIcon:SetImage(BACKUP_MATERIAL:GetName())
	self.Selection.PreviewIcon:SetTall(self.Selection.PreviewIcon:GetWide())
	self.Selection.PreviewIcon:SetVisible(false)
	self.Selection.PreviewIcon:Dock(TOP)
	self:RefreshSelection()
end

function PANEL:RefreshSelection()
	local selection = self.Selection
	local previewIcon = self.Selection.PreviewIcon
	for i, _ in ipairs(selection.MaterialList:GetLines()) do
		selection.MaterialList:RemoveLine(i)
	end

	for _, submaterialStruct in ipairs(self.submaterials) do
		---@type DListView_Line
		---@diagnostic disable-next-line
		local row = selection.MaterialList:AddLine(submaterialStruct[2], submaterialStruct[3])

		function row.OnSelect()
			---@type IMaterial
			---@diagnostic disable-next-line
			local material = row:GetValue(2)
			local aspectRatio = getAspectRatio(material)

			previewIcon:SetVisible(true)
			previewIcon:SetImage(material:GetName())
			previewIcon:SetTall(previewIcon:GetWide() / aspectRatio)
		end
	end
	selection.MaterialList:SetDirty(true)
end

function PANEL:RefreshGallery()
	if not IsValid(self.Entity) then
		return
	end

	local materials = self.Entity:GetMaterials()

	for i, materialPath in ipairs(materials) do
		local materialIcon = vgui.Create("DImageButton", self.Gallery.Grid)
		materialIcon:SetOnViewMaterial(materialPath, BACKUP_MATERIAL:GetName())
		materialIcon:SetStretchToFit(true)

		local material = getMaterial(materialPath)
		local aspectRatio = getAspectRatio(material)

		materialIcon:SetSize(aspectRatio * self.ButtonHeight, self.ButtonHeight)

		materialIcon.DoClick = function()
			if not self.submaterialSet[i - 1] then
				self.submaterialSet[i - 1] =
					table.insert(self.submaterials, { i - 1, shortPath(materialPath), material })
			else
				table.remove(self.submaterials, self.submaterialSet[i])
				self.submaterialSet[i - 1] = nil
				self:RefreshSubMaterialSet()
			end

			self:RefreshSelection()
		end

		materialIcon.TestHover = function(_, x, y)
			self.Tooltip:SetVisible(true)
			self.Tooltip:SetPos(x + 10, y - 0.55 * self.Tooltip:GetTall())
			self.Tooltip:SetText(shortPath(materialPath))
		end

		self.Gallery.Grid:Add(materialIcon)
	end
end

---@param entity Entity
function PANEL:SetEntity(entity)
	self.Entity = entity
	self:RefreshGallery()
end

function PANEL:OnRemove()
	self.Tooltip:Remove()
end

function PANEL:SetVisible(visible)
	---@diagnostic disable-next-line
	self.BaseClass.SetVisible(self, visible)
	self.Tooltip:SetVisible(visible)
end

vgui.Register("colortree_submaterials", PANEL, "DFrame")