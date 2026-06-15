------------------------------------------------------------
-- VeinCF :: ui_builder
-- Programmatic UMG widget construction from Lua.
--
-- Build full widget trees using StaticConstructObject +
-- StaticFindObject for each UMG class. No .uasset needed.
--
-- Usage:
--   local ub = require("modules.ui_builder")
--   local root = ub.canvas_panel(owner)
--   local box  = ub.vertical_box(owner)
--   ub.add_child_to_canvas(root, box, {
--       anchor_min = {0.5, 0.5}, anchor_max = {0.5, 0.5},
--       position = {-250, -225}, size = {500, 450},
--   })
--   ub.add_to_viewport(root, 100)
------------------------------------------------------------
local log = require("modules.log")

local M = {}

------------------------------------------------------------
-- Class cache
------------------------------------------------------------
local class_cache = {}

--- Find a UMG widget class by name.
--- @param class_name string  e.g. "CanvasPanel", "TextBlock", "Button"
--- @return UObject|nil
function M.find_class(class_name)
    if class_cache[class_name] then
        local c = class_cache[class_name]
        if c:IsValid() then return c end
        class_cache[class_name] = nil
    end

    -- UMG classes live under /Script/UMG
    local paths = {
        "/Script/UMG." .. class_name,
        "/Script/SlateCore." .. class_name,
        "/Script/Slate." .. class_name,
    }

    for _, path in ipairs(paths) do
        local ok, cls = pcall(StaticFindObject, path)
        if ok and cls and cls:IsValid() then
            class_cache[class_name] = cls
            log.debug("ui_builder", "Found class: %s -> %s", class_name, path)
            return cls
        end
    end

    log.error("ui_builder", "Could not find class: %s", class_name)
    return nil
end

--- Construct a widget of the given class.
--- @param class_name string  UMG class name
--- @param owner UObject      Owning object (PlayerController)
--- @return UObject|nil
function M.construct(class_name, owner)
    local cls = M.find_class(class_name)
    if not cls then return nil end

    local ok, widget = pcall(StaticConstructObject, cls, owner)
    if ok and widget and widget:IsValid() then
        return widget
    end
    log.error("ui_builder", "StaticConstructObject failed for %s: %s",
              class_name, tostring(widget))
    return nil
end

------------------------------------------------------------
-- Widget constructors (convenience)
------------------------------------------------------------

function M.canvas_panel(owner)
    return M.construct("CanvasPanel", owner)
end

function M.vertical_box(owner)
    return M.construct("VerticalBox", owner)
end

function M.horizontal_box(owner)
    return M.construct("HorizontalBox", owner)
end

function M.overlay(owner)
    return M.construct("Overlay", owner)
end

function M.border(owner)
    return M.construct("Border", owner)
end

function M.image(owner)
    return M.construct("Image", owner)
end

function M.text_block(owner)
    return M.construct("TextBlock", owner)
end

function M.button(owner)
    return M.construct("Button", owner)
end

function M.spacer(owner)
    return M.construct("Spacer", owner)
end

function M.size_box(owner)
    return M.construct("SizeBox", owner)
end

function M.scroll_box(owner)
    return M.construct("ScrollBox", owner)
end

------------------------------------------------------------
-- Hierarchy
------------------------------------------------------------

--- Add a child widget to a panel widget.
--- @param parent UObject  Parent panel
--- @param child UObject   Child widget
--- @return boolean
function M.add_child(parent, child)
    local ok, err = pcall(function()
        parent:AddChild(child)
    end)
    if not ok then
        log.error("ui_builder", "AddChild failed: %s", tostring(err))
    end
    return ok
end

--- Add widget to the viewport.
function M.add_to_viewport(widget, z_order)
    local ok, err = pcall(function()
        widget:AddToViewport(z_order or 0)
    end)
    if not ok then
        log.error("ui_builder", "AddToViewport failed: %s", tostring(err))
    end
    return ok
end

--- Remove widget from viewport.
function M.remove_from_viewport(widget)
    if widget and widget:IsValid() then
        pcall(function() widget:RemoveFromParent() end)
    end
end

------------------------------------------------------------
-- Slot configuration (CanvasPanelSlot)
------------------------------------------------------------

--- Configure a CanvasPanel slot after AddChild.
--- opts: anchor_min, anchor_max, position, size, alignment, auto_size
function M.set_canvas_slot(child, opts)
    local ok, err = pcall(function()
        local slot = child.Slot
        if not slot or not slot:IsValid() then
            log.warn("ui_builder", "No slot on child")
            return
        end

        if opts.anchor_min then
            local a = slot.Anchors
            a.Minimum.X = opts.anchor_min[1]
            a.Minimum.Y = opts.anchor_min[2]
            if opts.anchor_max then
                a.Maximum.X = opts.anchor_max[1]
                a.Maximum.Y = opts.anchor_max[2]
            else
                a.Maximum.X = opts.anchor_min[1]
                a.Maximum.Y = opts.anchor_min[2]
            end
            slot.Anchors = a
        end

        if opts.position then
            local off = slot.Offsets
            off.Left = opts.position[1]
            off.Top  = opts.position[2]
            slot.Offsets = off
        end

        if opts.size then
            local off = slot.Offsets
            off.Right  = opts.size[1]
            off.Bottom = opts.size[2]
            slot.Offsets = off
        end

        if opts.alignment then
            local al = slot.Alignment
            al.X = opts.alignment[1]
            al.Y = opts.alignment[2]
            slot.Alignment = al
        end

        if opts.auto_size ~= nil then
            slot.bAutoSize = opts.auto_size
        end
    end)
    if not ok then
        log.warn("ui_builder", "set_canvas_slot error: %s", tostring(err))
    end
end

------------------------------------------------------------
-- Property setters
------------------------------------------------------------

--- Set text on a TextBlock.
function M.set_text(text_block, text)
    pcall(function()
        text_block:SetText(text)
    end)
end

--- Set text color on a TextBlock (r,g,b,a in 0-1 range).
function M.set_text_color(text_block, r, g, b, a)
    pcall(function()
        text_block:SetColorAndOpacity({ R = r, G = g, B = b, A = a or 1.0 })
    end)
end

--- Set brush color on a Border or Image.
function M.set_brush_color(widget, r, g, b, a)
    pcall(function()
        widget:SetBrushColor({ R = r, G = g, B = b, A = a or 1.0 })
    end)
end

--- Set widget visibility.
--- vis: "Visible", "Collapsed", "Hidden", "HitTestInvisible", "SelfHitTestInvisible"
function M.set_visibility(widget, vis)
    pcall(function()
        widget:SetVisibility(vis)
    end)
end

--- Set padding on a Border widget.
function M.set_padding(border, left, top, right, bottom)
    pcall(function()
        border:SetPadding({ Left = left, Top = top or left,
                            Right = right or left, Bottom = bottom or top or left })
    end)
end

--- Set render opacity (0.0 - 1.0).
function M.set_opacity(widget, opacity)
    pcall(function()
        widget:SetRenderOpacity(opacity)
    end)
end

return M
