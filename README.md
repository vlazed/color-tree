# Tool Trees <!-- omit from toc -->

Access and modify an entity's children and its descendants through the Material, Model, or Color Tree tools, with a familiar user interface.

## Table of Contents <!-- omit from toc -->
- [Tool Trees](#tool-trees)
  - [Color Tree](#color-tree)
  - [Model Tree](#model-tree)
  - [Material Tree](#material-tree)
- [Disclaimer](#disclaimer)
- [Pull Requests](#pull-requests)

## Tool Trees
This addon consists of three tools:

- Color Tree,
- Model Tree, and
- Material Tree.

The key feature of these three tools is the ability to access the hierarchy of an entity and modify its colors, skin, bodygroups, or (sub)materials.

### Color Tree
![Color Tree Preview](/media/colortree-preview.png)

This tool sets the colors of an entity and its descendants.

This attempts to support addons that manipulate material proxies, such as
- [Hat Painter & Crit Glow Tools](https://steamcommunity.com/sharedfiles/filedetails/?id=135491961)
- [Cloak Effect Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=608061297)
- [Ragdoll Colorizer](https://steamcommunity.com/sharedfiles/filedetails/?id=267610127)
- [Stik's Tools Ragdoll Color](https://steamcommunity.com/sharedfiles/filedetails/?id=2402581521)

The tool also supports submaterial colouring if the [Advanced Colour Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=692778306) is installed. If it is installed, upon selecting an entity, the submaterial gallery from the [Material Tree](#material-tree) will pop up, allowing you to select a submaterial to modify its colors.

Unlike the Color Tool, which requires the user to click on the entity to change colors, copy colors, or reset colors, the Color Tree requires the user to click on the entity only once. Color changes to the entity will show when the user clicks on the color mixer. In addition, the color mixer will also update itself when the entity's color changes externally (either from another user or from an external process such as Stop Motion Helper playback). 

### Model Tree
![Model Tree Preview](/media/modeltree-preview.png)

This tool sets the skin, bodygroup, or model of the entity and its descendants.

Contrary to existing solutions (Composite Bonemerge Tool "injects" the bodygroups and skins to bonemerged entity), this tool gives direct access to the bonemerged entity, allowing you to set these properties directly, with no internal changes to the entity.

### Material Tree
![Material Tree Preview](/media/materialtree-preview.png)

This tool sets the materials or submaterials of the entity and its descendants.

Unlike the submaterial tool, which lists the paths of the submaterials to modify and requires a scrolling input for navigation, this tool instead presents a submaterial gallery for the user to select a submaterial to modify. In addition, the user can set the material of multiple submaterials at once, without the need to scroll and click to find a submaterial. 

## Disclaimer

These tools have no conflicts of interests with the tools that it supports. Support for the tools above has been achieved by downloading the aforementioned addons using [gmpublisher](https://github.com/WilliamVenner/gmpublisher) and reading their source code. These tool trees interface with the addon tools (if they are installed) by calling their functions or setting networked variables.

**This tool has been tested in singleplayer.** Although this tool may function in multiplayer, please expect bugs and report any that you observe in the issue tracker.

## Pull Requests

When making a pull request, make sure to confine to the style seen throughout. Try to add types for new functions or data structures. I used the default [StyLua](https://github.com/JohnnyMorganz/StyLua) formatting style.
