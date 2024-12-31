---@meta

---@generic T
---@alias Set<T> {[T]: true}

---@alias MaterialProxy string
---@alias ConVarName string
---@alias DermaClass string

---@alias DataApplier fun(ply: Player, ent: Entity, data: any)
---@alias DataResetter fun(ply: Player, ent: Entity, data: any)
---@alias DataTransformer fun(data: ProxyField): any

---Table of functions to transform entity proxy data and apply or reset it
---@alias ProxyTransformer {apply: DataApplier, transform: DataTransformer, reset: DataResetter}

---Mapping of material proxies to function tables that transforms data and applies proxies
---@alias ProxyTransformers {[MaterialProxy]: ProxyTransformer}

---@alias ProxyData {[ConVarName]: number|boolean}

---@alias ProxyField {color: Color, data: ProxyData}

---@alias ProxyColor {[MaterialProxy]: ProxyField}?

---The convar associated with the proxy with the suggested derma for controlling it
---@alias ProxyConVar {[1]: ConVarName, [2]: DermaClass}

---A mapping from the proxy name to an array of the convars and dermas for controlling it
---@alias ProxyConVarMap {[MaterialProxy]: table<ProxyConVar>}

---An entity that has a color method and fields from other addons
---@class Colorable: Entity
---@field ProxyentCritGlow Entity
---@field ProxyentPaintColor Entity
---@field colortree_owner Player

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
---@field renderMode number
---@field renderFx number
---@field proxyColor ProxyColor?
---@field children DescendantTree[]

---UI

---@alias ProxyDermas {[MaterialProxy]: Panel}

---Main control panel UI
---@class PanelChildren
---@field treePanel ColorTreePanel
---@field colorPicker ColorTreePicker
---@field renderMode DComboBox
---@field renderFx DComboBox
---@field proxySettings DForm
---@field proxySet DTextEntry
---@field proxyDermas ProxyDermas
---@field lock DCheckBoxLabel
---@field propagate DCheckBoxLabel
---@field reset DCheckBoxLabel

---Immutable properties of the panel
---@class PanelProps
---@field colorable Colorable|Entity

---Mutable properties of the panel
---@class PanelState
---@field haloedEntity Entity
---@field haloColor Color
---@field descendantTree DescendantTree?

---Wrapper for `DTree_Node`
---@class ColorTreePanel_Node: DTree_Node
---@field info DescendantTree
---@field Icon DImage
---@field GetChildNodes fun(self: ColorTreePanel_Node): ColorTreePanel_Node[]

---Wrapper for `DTree`
---@class ColorTreePanel: DTree
---@field ancestor ColorTreePanel_Node
---@field GetSelectedItem fun(self: ColorTreePanel): ColorTreePanel_Node

---Wrapper for `DColorMixer`
---@class ColorTreeMixer: DColorMixer
---@field HSV DSlider

---Wrapper for `CtrlColor`
---@class ColorTreePicker: Panel
---@field SetLabel fun(self: ColorTreePicker, label: string)
---@field Mixer ColorTreeMixer
