---@meta

---An entity that has a color method and fields from other addons
---@class Colorable: Entity
---@field ProxyentCritGlow Entity
---@field ProxyentPaintColor Entity
---@field colortree_owner Player

---@alias MaterialProxy string
---@alias ProxyColor {[MaterialProxy]: Color}?

---Dupe data for color trees
---@class ColorTreeData
---@field colortree_color Color
---@field colortree_renderMode number
---@field colortree_renderFx number
---@field colortree_proxyColor ProxyColor

---Main structure representing an entity's color tree
---@class DescendantTree
---@field parent integer?
---@field route integer[]?
---@field entity integer
---@field color Color
---@field renderMode number|RENDERMODE
---@field renderFx number|kRenderFx
---@field proxyColor ProxyColor?
---@field children DescendantTree[]

---Wrapper for `DTree_Node`
---@class ColorTreePanel_Node: DTree_Node
---@field info DescendantTree
---@field Icon DImage
---@field GetChildNodes fun(self: ColorTreePanel_Node): ColorTreePanel_Node[]

---Wrapper for `DTree`
---@class ColorTreePanel: DTree
---@field ancestor ColorTreePanel_Node
---@field GetSelectedItem fun(self: ColorTreePanel): ColorTreePanel_Node

---Wrapper for `CtrlColor`
---@class ColorTreePicker: Panel
---@field SetLabel fun(self: ColorTreePicker, label: string)
