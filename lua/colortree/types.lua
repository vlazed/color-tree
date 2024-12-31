---@meta

---@generic T
---@alias Set<T> {[T]: true}

---@alias MaterialProxy string
---@alias ConVarName string
---@alias DermaClass string

---@alias DataApplier fun(ply: Player, ent: Entity, data: any)
---@alias DataResetter fun(ply: Player, ent: Entity, data: any)
---@alias DataTransformer fun(data: ProxyField): any

---@alias Model string Path to the model
---@alias Bodygroups string Bodygroup submodel ids
---@alias Skin number Skin index

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
---@class ColorTree
---@field parent integer?
---@field route integer[]?
---@field entity integer
---@field color Color
---@field renderMode number
---@field renderFx number
---@field proxyColor ProxyColor?
---@field children ColorTree[]

---Dupe data for model trees
---@class ModelTreeData
---@field modeltree_model Model
---@field modeltree_defaultmodel Model
---@field modeltree_skin Skin
---@field modeltree_bodygroups Bodygroups

---Main structure representing an entity's model tree
---@class ModelTree
---@field parent integer?
---@field route integer[]?
---@field entity integer
---@field model Model
---@field defaultModel Model
---@field defaultSkin Skin
---@field defaultBodygroups Bodygroups
---@field bodygroups Bodygroups
---@field bodygroupData BodyGroupData[]
---@field skin Skin
---@field children ModelTree[]

---UI

---@alias ProxyDermas {[MaterialProxy]: Panel}

---Main color control panel UI
---@class ColorPanelChildren
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

---Immutable properties of the color panel
---@class ColorPanelProps
---@field colorable Colorable|Entity

---Mutable properties of the color panel
---@class ColorPanelState
---@field haloedEntity Entity
---@field haloColor Color
---@field colorTree ColorTree?

---TODO: When LuaLS supports generic fields, rework the following below to reduce boilerplate

---Wrapper for `DTree_Node`
---@class ColorTreePanel_Node: DTree_Node
---@field info ColorTree
---@field Icon DImage
---@field GetChildNodes fun(self: ColorTreePanel_Node): ColorTreePanel_Node[]

---Wrapper for `DTree`
---@class ColorTreePanel: DTree
---@field ancestor ColorTreePanel_Node
---@field GetSelectedItem fun(self: ColorTreePanel): ColorTreePanel_Node

---Wrapper for `DTree_Node`
---@class ModelTreePanel_Node: DTree_Node
---@field info ModelTree
---@field Icon DImage
---@field GetChildNodes fun(self: ModelTreePanel_Node): ModelTreePanel_Node[]

---Wrapper for `DTree`
---@class ModelTreePanel: DTree
---@field ancestor ModelTreePanel_Node
---@field GetSelectedItem fun(self: ModelTreePanel): ModelTreePanel_Node

---END TODO

---Wrapper for `DColorMixer`
---@class ColorTreeMixer: DColorMixer
---@field HSV DSlider

---Wrapper for `CtrlColor`
---@class ColorTreePicker: Panel
---@field SetLabel fun(self: ColorTreePicker, label: string)
---@field Mixer ColorTreeMixer

---Main model control panel UI
---@class ModelPanelChildren
---@field treePanel ModelTreePanel
---@field modelForm DForm
---@field modelEntry DTextEntry
---@field lock DCheckBoxLabel

---Immutable properties of the color panel
---@class ModelPanelProps
---@field modelEntity Entity

---Mutable properties of the color panel
---@class ModelPanelState
---@field haloedEntity Entity
---@field haloColor Color
---@field modelTree ModelTree?
