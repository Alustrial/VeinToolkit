------------------------------------------------------------
-- VeinCF :: ui
-- Manages in-game UE5 native UMG widget panels.
--
-- Two paths supported:
--   1. Blueprint widgets — LoadAsset a .uasset Widget Blueprint
--      class, StaticConstructObject it, AddToViewport. This is
--      the Ramjet pattern and the recommended path for UI designers.
--   2. Lua-built widgets — StaticConstructObject individual UMG
--      classes (TextBlock, Button, CanvasPanel, etc.) and build
--      the widget tree from Lua. For backend developers.
--
-- API:
--   ui.create_widget(owner)           — create a blank UUserWidget
--   ui.load_widget_class(asset_path)  — load a Blueprint widget class
--   ui.show_widget(widget)            — AddToViewport
--   ui.hide_widget(widget)            — RemoveFromParent
--   ui.toggle_widget(widget)          — show/hide toggle
--   ui.is_available()                 — true if widget creation works
--
-- Require as: require("modules.ui")
------------------------------------------------------------
local log = require("modules.log")

local M = {}

--- Cache for the UUserWidget class
local UserWidgetClass = nil

local function get_user_widget_class()
    if UserWidgetClass and UserWidgetClass:IsValid() then
        return UserWidgetClass
    end
    UserWidgetClass = StaticFindObject("/Script/UMG.UserWidget")
    if not UserWidgetClass or not UserWidgetClass:IsValid() then
        UserWidgetClass = StaticFindObject("/Script/UMG.Default__UserWidget")
    end
    return UserWidgetClass
end

------------------------------------------------------------
-- Widget creation
------------------------------------------------------------

--- Create a blank UUserWidget.
--- @param owner UObject  The owning player controller
--- @return UObject|nil   The created widget, or nil on failure
function M.create_widget(owner)
    local cls = get_user_widget_class()
    if not cls or not cls:IsValid() then
        log.error("ui", "Could not find UUserWidget class")
        return nil
    end
    local ok, widget = pcall(StaticConstructObject, cls, owner)
    if ok and widget and widget:IsValid() then
        return widget
    end
    log.error("ui", "StaticConstructObject failed: %s", tostring(widget))
    return nil
end

--- Load a Blueprint widget class from an asset path.
--- @param asset_path string  e.g. "/Game/VeinCF/UI/WBP_AdminPanel.WBP_AdminPanel_C"
--- @return UObject|nil       The loaded class, or nil
function M.load_widget_class(asset_path)
    if not LoadAsset then
        log.error("ui", "LoadAsset not available")
        return nil
    end
    local ok, cls = pcall(LoadAsset, asset_path)
    if ok and cls and cls:IsValid() then
        return cls
    end
    log.error("ui", "Failed to load widget class: %s", asset_path)
    return nil
end

--- Create a widget from a Blueprint class and add to viewport.
--- @param class_path string  Asset path to the Widget Blueprint class
--- @param owner UObject      Owning player controller
--- @param z_order number?    Viewport Z order (default 0)
--- @return UObject|nil
function M.create_blueprint_widget(class_path, owner, z_order)
    local cls = M.load_widget_class(class_path)
    if not cls then return nil end

    local ok, widget = pcall(StaticConstructObject, cls, owner)
    if not ok or not widget or not widget:IsValid() then
        log.error("ui", "Failed to construct widget from %s", class_path)
        return nil
    end

    M.show_widget(widget, z_order)
    return widget
end

--- Add a widget to the viewport
function M.show_widget(widget, z_order)
    if widget and widget:IsValid() then
        local ok, err = pcall(function()
            widget:AddToViewport(z_order or 0)
        end)
        if not ok then
            log.error("ui", "AddToViewport failed: %s", tostring(err))
        end
    end
end

--- Remove a widget from the viewport
function M.hide_widget(widget)
    if widget and widget:IsValid() then
        pcall(function() widget:RemoveFromParent() end)
    end
end

--- Toggle widget visibility
function M.toggle_widget(widget, z_order)
    if not widget or not widget:IsValid() then return end
    -- Try checking if in viewport
    local ok, in_vp = pcall(function() return widget:IsInViewport() end)
    if ok and in_vp then
        M.hide_widget(widget)
    else
        M.show_widget(widget, z_order)
    end
end

------------------------------------------------------------
-- Query
------------------------------------------------------------

function M.is_available()
    return StaticConstructObject ~= nil and StaticFindObject ~= nil
end

return M
