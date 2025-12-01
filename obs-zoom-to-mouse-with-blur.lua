--
-- OBS Zoom to Mouse (Modified with Motion Blur)
-- An OBS lua script to zoom a display-capture source to focus on the mouse.
-- Copyright (c) BlankSourceCode.  All rights reserved.
-- Modified to support Motion Blur control and Directional Blur.
--

local obs = obslua or obs
local ffi = require("ffi")
local VERSION = "2.2.2-DirBlur-FIX-V2" -- Updated version after core logic fix
local CROP_FILTER_NAME = "obs-zoom-to-mouse-crop"

local socket_available, socket = pcall(require, "ljsocket")
local socket_server = nil
local socket_mouse = nil

local source_name = ""
local source = nil
local sceneitem = nil
local sceneitem_info_orig = nil
local sceneitem_crop_orig = nil
local sceneitem_info = nil
local sceneitem_crop = nil
local crop_filter = nil
local crop_filter_temp = nil
local crop_filter_settings = nil
local crop_filter_info_orig = { x = 0, y = 0, w = 0, h = 0 }
local crop_filter_info = { x = 0, y = 0, w = 0, h = 0 }
local monitor_info = nil
local zoom_info = {
    source_size = { width = 0, height = 0 },
    source_crop = { x = 0, y = 0, w = 0, h = 0 },
    source_crop_filter = { x = 0, y = 0, w = 0, h = 0 },
    zoom_to = 2
}
local zoom_time = 0
local zoom_target = nil
local locked_center = nil
local locked_last_pos = nil
local hotkey_zoom_id = nil
local hotkey_follow_id = nil
local is_timer_running = false
local FRAME_TIME_SCALE = 10 -- Used to control the speed of the zoom animation over time.

local win_point = nil
local x11_display = nil
local x11_root = nil
local x11_mouse = nil
local osx_lib = nil
local osx_nsevent = nil
local osx_mouse_location = nil

local use_auto_follow_mouse = true
local use_follow_outside_bounds = false
local is_following_mouse = false
local follow_speed = 0.1
local follow_border = 0
local follow_safezone_sensitivity = 10
local use_follow_auto_lock = false
local zoom_value = 2
local zoom_speed = 0.1
local allow_all_sources = false
local use_monitor_override = false
local monitor_override_x = 0
local monitor_override_y = 0
local monitor_override_w = 0
local monitor_override_h = 0
local monitor_override_sx = 0
local monitor_override_sy = 0
local monitor_override_dw = 0
local monitor_override_dh = 0
local use_socket = false
local socket_port = 0
local socket_poll = 1000
local debug_logs = false
local is_obs_loaded = false
local is_script_loaded = false

-- Motion Blur Variables
local use_motion_blur = false
local motion_blur_strength = 1.0
local motion_blur_filter_name = "Motion Blur"
local motion_blur_param_name = "Size" -- Parameter name to control (e.g. 'Size', 'radius', 'kawase_passes')
local blur_filter = nil
local blur_filter_settings = nil
local last_blur_pos = { x = 0, y = 0 }

-- Motion Blur Directional Control (NEW)
local use_directional_blur = false
local blur_angle_param_name = "angle" -- Parameter name to control the angle of the blur (e.g. 'angle', 'direction')

local ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
local zoom_state = ZoomState.None

local version = obs.obs_get_version_string()
local major_num, minor_num, patch_num = version:match("(%d+)%.(%d+)%.?(%d*)")
local major = tonumber(major_num) or 0
local minor = tonumber(minor_num) or 0
local patch = tonumber(patch_num) or 0
local version_number = major * 100 + minor

-- Define the mouse cursor functions for each platform
if ffi.os == "Windows" then
    ffi.cdef([[
        typedef int BOOL;
        typedef struct{
            long x;
            long y;
        } POINT, *LPPOINT;
        BOOL GetCursorPos(LPPOINT);
    ]])
    win_point = ffi.new("POINT[1]")
elseif ffi.os == "Linux" then
    ffi.cdef([[
        typedef unsigned long XID;
        typedef XID Window;
        typedef void Display;
        Display* XOpenDisplay(char*);
        XID XDefaultRootWindow(Display *display);
        int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        int XCloseDisplay(Display*);
    ]])

    x11_lib = ffi.load("X11.so.6")
    if x11_lib then
        x11_display = x11_lib.XOpenDisplay(nil)
        if x11_display ~= nil then
            x11_root = x11_lib.XDefaultRootWindow(x11_display)
            x11_mouse = {
                root_win = ffi.new("Window[1]"),
                child_win = ffi.new("Window[1]"),
                root_x = ffi.new("int[1]"),
                root_y = ffi.new("int[1]"),
                win_x = ffi.new("int[1]"),
                win_y = ffi.new("int[1]"),
                mask = ffi.new("unsigned int[1]")
            }
        end
    end
elseif ffi.os == "OSX" then
    ffi.cdef([[
        typedef struct {
            double x;
            double y;
        } CGPoint;
        typedef void* SEL;
        typedef void* id;
        typedef void* Method;

        SEL sel_registerName(const char *str);
        id objc_getClass(const char*);
        Method class_getClassMethod(id cls, SEL name);
        void* method_getImplementation(Method);
        int access(const char *path, int amode);
    ]])

    osx_lib = ffi.load("libobjc")
    if osx_lib ~= nil then
        osx_nsevent = {
            class = osx_lib.objc_getClass("NSEvent"),
            sel = osx_lib.sel_registerName("mouseLocation")
        }
        local method = osx_lib.class_getClassMethod(osx_nsevent.class, osx_nsevent.sel)
        if method ~= nil then
            local imp = osx_lib.method_getImplementation(method)
            osx_mouse_location = ffi.cast("CGPoint(*)(void*, void*)", imp)
        end
    end
end

---
-- Get the current mouse position
---@return table Mouse position
function get_mouse_pos()
    local mouse = { x = 0, y = 0 }

    if socket_mouse ~= nil then
        mouse.x = socket_mouse.x
        mouse.y = socket_mouse.y
    else
        if ffi.os == "Windows" then
            if win_point and ffi.C.GetCursorPos(win_point) ~= 0 then
                mouse.x = win_point[0].x
                mouse.y = win_point[0].y
            end
        elseif ffi.os == "Linux" then
            if x11_lib ~= nil and x11_display ~= nil and x11_root ~= nil and x11_mouse ~= nil then
                if x11_lib.XQueryPointer(x11_display, x11_root, x11_mouse.root_win, x11_mouse.child_win, x11_mouse.root_x, x11_mouse.root_y, x11_mouse.win_x, x11_mouse.win_y, x11_mouse.mask) ~= 0 then
                    mouse.x = tonumber(x11_mouse.win_x[0])
                    mouse.y = tonumber(x11_mouse.win_y[0])
                end
            end
        elseif ffi.os == "OSX" then
            if osx_lib ~= nil and osx_nsevent ~= nil and osx_mouse_location ~= nil then
                local point = osx_mouse_location(osx_nsevent.class, osx_nsevent.sel)
                mouse.x = point.x
                if monitor_info ~= nil then
                    if monitor_info.display_height > 0 then
                        mouse.y = monitor_info.display_height - point.y
                    else
                        mouse.y = monitor_info.height - point.y
                    end
                end
            end
        end
    end

    return mouse
end

---
-- Get the information about display capture sources for the current platform
---@return any
function get_dc_info()
    if ffi.os == "Windows" then
        return {
            source_id = "monitor_capture",
            prop_id = "monitor_id",
            prop_type = "string"
        }
    elseif ffi.os == "Linux" then
        return {
            source_id = "xshm_input",
            prop_id = "screen",
            prop_type = "int"
        }
    elseif ffi.os == "OSX" then
        if version_number >= 2901 then
            return {
                source_id = "screen_capture",
                prop_id = "display_uuid",
                prop_type = "string"
            }
        else
            return {
                source_id = "display_capture",
                prop_id = "display",
                prop_type = "int"
            }
        end
    end
    return nil
end

---
-- Logs a message to the OBS script console
---@param msg string The message to log
function log(msg)
    if debug_logs then
        obs.script_log(obs.OBS_LOG_INFO, msg)
    end
end

function format_table(tbl, indent)
    if not indent then
        indent = 0
    end

    local str = "{\n"
    for key, value in pairs(tbl) do
        local tabs = string.rep("  ", indent + 1)
        if type(value) == "table" then
            str = str .. tabs .. key .. " = " .. format_table(value, indent + 1) .. ",\n"
        else
            str = str .. tabs .. key .. " = " .. tostring(value) .. ",\n"
        end
    end
    str = str .. string.rep("  ", indent) .. "}"

    return str
end

function lerp(v0, v1, t)
    return v0 * (1 - t) + v1 * t;
end

function ease_in_out(t)
    t = t * 2
    if t < 1 then
        return 0.5 * t * t * t
    else
        t = t - 2
        return 0.5 * (t * t * t + 2)
    end
end

function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

function get_monitor_info(source)
    local info = nil
    if is_display_capture(source) and not use_monitor_override then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            local props = obs.obs_source_properties(source)
            if props ~= nil then
                local monitor_id_prop = obs.obs_properties_get(props, dc_info.prop_id)
                if monitor_id_prop then
                    local found = nil
                    local settings = obs.obs_source_get_settings(source)
                    if settings ~= nil then
                        local to_match
                        if dc_info.prop_type == "string" then
                            to_match = obs.obs_data_get_string(settings, dc_info.prop_id)
                        elseif dc_info.prop_type == "int" then
                            to_match = obs.obs_data_get_int(settings, dc_info.prop_id)
                        end

                        local item_count = obs.obs_property_list_item_count(monitor_id_prop);
                        for i = 0, item_count do
                            local name = obs.obs_property_list_item_name(monitor_id_prop, i)
                            local value
                            if dc_info.prop_type == "string" then
                                value = obs.obs_property_list_item_string(monitor_id_prop, i)
                            elseif dc_info.prop_type == "int" then
                                value = obs.obs_property_list_item_int(monitor_id_prop, i)
                            end

                            if value == to_match then
                                found = name
                                break
                            end
                        end
                        obs.obs_data_release(settings)
                    end

                    if found then
                        log("Parsing display name: " .. found)
                        local x, y = found:match("(-?%d+),(-?%d+)")
                        local width, height = found:match("(%d+)x(%d+)")

                        info = { x = 0, y = 0, width = 0, height = 0 }
                        info.x = tonumber(x, 10) or 0
                        info.y = tonumber(y, 10) or 0
                        info.width = tonumber(width, 10) or 0
                        info.height = tonumber(height, 10) or 0
                        info.scale_x = 1
                        info.scale_y = 1
                        info.display_width = info.width
                        info.display_height = info.height

                        log("Parsed the following display information\n" .. format_table(info))

                        if info.width == 0 and info.height == 0 then
                            info = nil
                        end
                    end
                end

                obs.obs_properties_destroy(props)
            end
        end
    end

    if use_monitor_override then
        info = {
            x = monitor_override_x,
            y = monitor_override_y,
            width = monitor_override_w,
            height = monitor_override_h,
            scale_x = monitor_override_sx,
            scale_y = monitor_override_sy,
            display_width = monitor_override_dw,
            display_height = monitor_override_dh
        }
    end

    if not info then
        log("WARNING: Could not auto calculate zoom source position and size.")
    end

    return info
end

function is_display_capture(source_to_check)
    if source_to_check ~= nil then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            if allow_all_sources then
                local source_type = obs.obs_source_get_id(source_to_check)
                if source_type == dc_info.source_id then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

function release_sceneitem()
    if is_timer_running then
        obs.timer_remove(on_timer)
        is_timer_running = false
    end

    -- Release blur filter if we held it
    if blur_filter ~= nil then
        -- Reset blur to 0 before releasing
        set_blur_intensity(0)
        -- Reset angle to 0 before releasing (NEW)
        if blur_filter_settings and use_directional_blur and blur_angle_param_name ~= "" then
            obs.obs_data_set_double(blur_filter_settings, blur_angle_param_name, 0)
            obs.obs_source_update(blur_filter, blur_filter_settings)
        end
        obs.obs_source_release(blur_filter)
        blur_filter = nil
        if blur_filter_settings then
             obs.obs_data_release(blur_filter_settings)
             blur_filter_settings = nil
        end
    end

    zoom_state = ZoomState.None

    if sceneitem ~= nil then
        if crop_filter ~= nil and source ~= nil then
            log("Zoom crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter)
            obs.obs_source_release(crop_filter)
            crop_filter = nil
        end

        if crop_filter_temp ~= nil and source ~= nil then
            log("Conversion crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter_temp)
            obs.obs_source_release(crop_filter_temp)
            crop_filter_temp = nil
        end

        if crop_filter_settings ~= nil then
            obs.obs_data_release(crop_filter_settings)
            crop_filter_settings = nil
        end

        if sceneitem_info_orig ~= nil then
            obs.obs_sceneitem_set_pos(sceneitem, sceneitem_info_orig.pos)
            obs.obs_sceneitem_set_scale(sceneitem, sceneitem_info_orig.scale)
            obs.obs_sceneitem_set_bounds(sceneitem, sceneitem_info_orig.bounds)
            obs.obs_sceneitem_set_rot(sceneitem, sceneitem_info_orig.rot)
            obs.obs_sceneitem_set_alignment(sceneitem, sceneitem_info_orig.alignment)
            obs.obs_sceneitem_set_bounds_type(sceneitem, sceneitem_info_orig.bounds_type)
            obs.obs_sceneitem_set_bounds_alignment(sceneitem, sceneitem_info_orig.bounds_alignment)
            sceneitem_info_orig = nil
        end

        if sceneitem_crop_orig ~= nil then
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop_orig)
            sceneitem_crop_orig = nil
        end

        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end

    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end

function refresh_sceneitem(find_newest)
    local source_raw = { width = 0, height = 0 }

    if find_newest then
        release_sceneitem()

        if source_name == "obs-zoom-to-mouse-none" then
            return
        end

        log("Finding sceneitem for Zoom Source '" .. source_name .. "'")
        if source_name ~= nil then
            source = obs.obs_get_source_by_name(source_name)
            if source ~= nil then
                source_raw.width = obs.obs_source_get_width(source)
                source_raw.height = obs.obs_source_get_height(source)

                -- Look for Blur Filter here
                if use_motion_blur then
                    blur_filter = obs.obs_source_get_filter_by_name(source, motion_blur_filter_name)
                    if blur_filter then
                        log("Found Motion Blur filter: " .. motion_blur_filter_name)
                        blur_filter_settings = obs.obs_source_get_settings(blur_filter)
                        -- Added for debugging, shows all parameters:
                        -- if blur_filter_settings then log("FILTER SETTINGS DUMP: " .. obs.obs_data_get_json(blur_filter_settings)) end
                    else
                        log("WARNING: Motion Blur enabled but filter '".. motion_blur_filter_name .."' not found on source.")
                    end
                end

                local scene_source = obs.obs_frontend_get_current_scene()
                if scene_source ~= nil then
                    local function find_scene_item_by_name(root_scene)
                        local queue = {}
                        table.insert(queue, root_scene)

                        while #queue > 0 do
                            local s = table.remove(queue, 1)
                            local found = obs.obs_scene_find_source(s, source_name)
                            if found ~= nil then
                                obs.obs_sceneitem_addref(found)
                                return found
                            end

                            local all_items = obs.obs_scene_enum_items(s)
                            if all_items then
                                for _, item in pairs(all_items) do
                                    local nested = obs.obs_sceneitem_get_source(item)
                                    if nested ~= nil then
                                        if obs.obs_source_is_scene(nested) then
                                            local nested_scene = obs.obs_scene_from_source(nested)
                                            table.insert(queue, nested_scene)
                                        elseif obs.obs_source_is_group(nested) then
                                            local nested_scene = obs.obs_group_from_source(nested)
                                            table.insert(queue, nested_scene)
                                        end
                                    end
                                end
                                obs.sceneitem_list_release(all_items)
                            end
                        end
                        return nil
                    end

                    local current = obs.obs_scene_from_source(scene_source)
                    sceneitem = find_scene_item_by_name(current)
                    obs.obs_source_release(scene_source)
                end

                if not sceneitem then
                    log("WARNING: Source not part of the current scene hierarchy.")
                    obs.obs_sceneitem_release(sceneitem)
                    obs.obs_source_release(source)
                    if blur_filter then
                        obs.obs_source_release(blur_filter)
                        blur_filter = nil
                    end
                    sceneitem = nil
                    source = nil
                    return
                end
            end
        end
    end

    if not monitor_info then
        monitor_info = get_monitor_info(source)
    end

    local is_non_display_capture = not is_display_capture(source)

    if sceneitem ~= nil then
        sceneitem_info_orig = {
            pos = obs.vec2(),
            scale = obs.vec2(),
            bounds = obs.vec2(),
            rot = 0,
            alignment = 0,
            bounds_type = 0,
            bounds_alignment = 0
        }
        obs.obs_sceneitem_get_pos(sceneitem, sceneitem_info_orig.pos)
        obs.obs_sceneitem_get_scale(sceneitem, sceneitem_info_orig.scale)
        obs.obs_sceneitem_get_bounds(sceneitem, sceneitem_info_orig.bounds)
        sceneitem_info_orig.rot = obs.obs_sceneitem_get_rot(sceneitem)
        sceneitem_info_orig.alignment = obs.obs_sceneitem_get_alignment(sceneitem)
        sceneitem_info_orig.bounds_type = obs.obs_sceneitem_get_bounds_type(sceneitem)
        sceneitem_info_orig.bounds_alignment = obs.obs_sceneitem_get_bounds_alignment(sceneitem)

        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        if is_non_display_capture then
            sceneitem_crop_orig.left = 0
            sceneitem_crop_orig.top = 0
            sceneitem_crop_orig.right = 0
            sceneitem_crop_orig.bottom = 0
        end

        sceneitem_info = {
            pos = obs.vec2(),
            scale = obs.vec2(),
            bounds = obs.vec2(),
            rot = 0,
            alignment = 0,
            bounds_type = 0,
            bounds_alignment = 0
        }
        obs.obs_sceneitem_get_pos(sceneitem, sceneitem_info.pos)
        obs.obs_sceneitem_get_scale(sceneitem, sceneitem_info.scale)
        obs.obs_sceneitem_get_bounds(sceneitem, sceneitem_info.bounds)
        sceneitem_info.rot = obs.obs_sceneitem_get_rot(sceneitem)
        sceneitem_info.alignment = obs.obs_sceneitem_get_alignment(sceneitem)
        sceneitem_info.bounds_type = obs.obs_sceneitem_get_bounds_type(sceneitem)
        sceneitem_info.bounds_alignment = obs.obs_sceneitem_get_bounds_alignment(sceneitem)

        sceneitem_crop = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop)

        if not source then
            log("ERROR: Could not get source for sceneitem (" .. source_name .. ")")
        end

        local source_width = obs.obs_source_get_base_width(source)
        local source_height = obs.obs_source_get_base_height(source)

        if source_width == 0 then source_width = source_raw.width end
        if source_height == 0 then source_height = source_raw.height end

        if source_width == 0 or source_height == 0 then
            if monitor_info ~= nil and monitor_info.width > 0 and monitor_info.height > 0 then
                source_width = monitor_info.width
                source_height = monitor_info.height
            end
        end

        if sceneitem_info.bounds_type == obs.OBS_BOUNDS_NONE then
            sceneitem_info.bounds_type = obs.OBS_BOUNDS_SCALE_INNER
            sceneitem_info.bounds_alignment = 5
            sceneitem_info.bounds.x = source_width * sceneitem_info.scale.x
            sceneitem_info.bounds.y = source_height * sceneitem_info.scale.y

            obs.obs_sceneitem_set_bounds_type(sceneitem, sceneitem_info.bounds_type)
            obs.obs_sceneitem_set_bounds_alignment(sceneitem, sceneitem_info.bounds_alignment)
            obs.obs_sceneitem_set_bounds(sceneitem, sceneitem_info.bounds)
        end

        zoom_info.source_crop_filter = { x = 0, y = 0, w = 0, h = 0 }
        local found_crop_filter = false
        local filters = obs.obs_source_enum_filters(source)
        if filters ~= nil then
            for k, v in pairs(filters) do
                local id = obs.obs_source_get_id(v)
                if id == "crop_filter" then
                    local name = obs.obs_source_get_name(v)
                    if name ~= CROP_FILTER_NAME and name ~= "temp_" .. CROP_FILTER_NAME then
                        found_crop_filter = true
                        local settings = obs.obs_source_get_settings(v)
                        if settings ~= nil then
                            if not obs.obs_data_get_bool(settings, "relative") then
                                zoom_info.source_crop_filter.x = zoom_info.source_crop_filter.x + obs.obs_data_get_int(settings, "left")
                                zoom_info.source_crop_filter.y = zoom_info.source_crop_filter.y + obs.obs_data_get_int(settings, "top")
                                zoom_info.source_crop_filter.w = zoom_info.source_crop_filter.w + obs.obs_data_get_int(settings, "cx")
                                zoom_info.source_crop_filter.h = zoom_info.source_crop_filter.h + obs.obs_data_get_int(settings, "cy")
                            end
                            obs.obs_data_release(settings)
                        end
                    end
                end
            end
            obs.source_list_release(filters)
        end

        if not found_crop_filter and (sceneitem_crop_orig.left ~= 0 or sceneitem_crop_orig.top ~= 0 or sceneitem_crop_orig.right ~= 0 or sceneitem_crop_orig.bottom ~= 0) then
            source_width = source_width - (sceneitem_crop_orig.left + sceneitem_crop_orig.right)
            source_height = source_height - (sceneitem_crop_orig.top + sceneitem_crop_orig.bottom)

            zoom_info.source_crop_filter.x = sceneitem_crop_orig.left
            zoom_info.source_crop_filter.y = sceneitem_crop_orig.top
            zoom_info.source_crop_filter.w = source_width
            zoom_info.source_crop_filter.h = source_height

            local settings = obs.obs_data_create()
            obs.obs_data_set_bool(settings, "relative", false)
            obs.obs_data_set_int(settings, "left", zoom_info.source_crop_filter.x)
            obs.obs_data_set_int(settings, "top", zoom_info.source_crop_filter.y)
            obs.obs_data_set_int(settings, "cx", zoom_info.source_crop_filter.w)
            obs.obs_data_set_int(settings, "cy", zoom_info.source_crop_filter.h)
            crop_filter_temp = obs.obs_source_create_private("crop_filter", "temp_" .. CROP_FILTER_NAME, settings)
            obs.obs_source_filter_add(source, crop_filter_temp)
            obs.obs_data_release(settings)

            sceneitem_crop.left = 0
            sceneitem_crop.top = 0
            sceneitem_crop.right = 0
            sceneitem_crop.bottom = 0
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop)
        elseif found_crop_filter then
            source_width = zoom_info.source_crop_filter.w
            source_height = zoom_info.source_crop_filter.h
        end

        zoom_info.source_size = { width = source_width, height = source_height }
        zoom_info.source_crop = {
            l = sceneitem_crop_orig.left,
            t = sceneitem_crop_orig.top,
            r = sceneitem_crop_orig.right,
            b = sceneitem_crop_orig.bottom
        }

        crop_filter_info_orig = { x = 0, y = 0, w = zoom_info.source_size.width, h = zoom_info.source_size.height }
        crop_filter_info = {
            x = crop_filter_info_orig.x,
            y = crop_filter_info_orig.y,
            w = crop_filter_info_orig.w,
            h = crop_filter_info_orig.h
        }

        -- Initialize blur pos tracker to current crop position
        last_blur_pos.x = crop_filter_info.x
        last_blur_pos.y = crop_filter_info.y

        crop_filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
        if crop_filter == nil then
            crop_filter_settings = obs.obs_data_create()
            obs.obs_data_set_bool(crop_filter_settings, "relative", false)
            crop_filter = obs.obs_source_create_private("crop_filter", CROP_FILTER_NAME, crop_filter_settings)
            obs.obs_source_filter_add(source, crop_filter)
        else
            crop_filter_settings = obs.obs_source_get_settings(crop_filter)
        end

        obs.obs_source_filter_set_order(source, crop_filter, obs.OBS_ORDER_MOVE_BOTTOM)
        set_crop_settings(crop_filter_info_orig)
    end
end

function get_target_position(zoom)
    local mouse = get_mouse_pos()

    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end

    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    local new_size = {
        width = zoom.source_size.width / zoom.zoom_to,
        height = zoom.source_size.height / zoom.zoom_to
    }

    local pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    local crop = {
        x = pos.x,
        y = pos.y,
        w = new_size.width,
        h = new_size.height,
    }

    crop.x = math.floor(clamp(0, (zoom.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom.source_size.height - new_size.height), crop.y))

    return { crop = crop, raw_center = mouse, clamped_center = { x = math.floor(crop.x + crop.w * 0.5), y = math.floor(crop.y + crop.h * 0.5) } }
end

function on_toggle_follow(pressed)
    if pressed and zoom_state == ZoomState.ZoomedIn then
        is_following_mouse = not is_following_mouse
        log("Tracking mouse is " .. (is_following_mouse and "on" or "off"))

        if is_following_mouse then
            -- Make sure timer is running if we are zoomed in and start following
            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

function on_toggle_zoom(pressed)
    if pressed then
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.None then
            if zoom_state == ZoomState.ZoomedIn then
                log("Zooming out")
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
                if is_following_mouse then
                    is_following_mouse = false
                    log("Tracking mouse is off (due to zoom out)")
                end
            else
                log("Zooming in")
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                -- Calculate initial target position
                zoom_target = get_target_position(zoom_info)
            end

            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

function set_blur_intensity(val)
    if blur_filter and blur_filter_settings then
        if motion_blur_param_name == "kawase_passes" then
            -- For integer-based parameters like kawase_passes
            local int_val = math.floor(val)
            obs.obs_data_set_int(blur_filter_settings, motion_blur_param_name, int_val)
        else
            -- For float-based parameters like radius or Size
            obs.obs_data_set_double(blur_filter_settings, motion_blur_param_name, val)
        end
        obs.obs_source_update(blur_filter, blur_filter_settings)
    end
end

function on_timer()
    if crop_filter_info == nil or zoom_target == nil then
        -- This should not happen if the script is loaded correctly, but safe guard.
        if is_timer_running then
             obs.timer_remove(on_timer)
             is_timer_running = false
        end
        return
    end

    -- Store pre-update crop position for blur calc
    local prev_x = crop_filter_info.x
    local prev_y = crop_filter_info.y
    
    local dx = 0
    local dy = 0

    if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
        if zoom_time <= 1 then
            if zoom_state == ZoomState.ZoomingIn and use_auto_follow_mouse then
                -- Recalculate target while zooming in to track mouse immediately
                zoom_target = get_target_position(zoom_info)
            end
            
            crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, ease_in_out(zoom_time))
            crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, ease_in_out(zoom_time))
            crop_filter_info.w = lerp(crop_filter_info.w, zoom_target.crop.w, ease_in_out(zoom_time))
            crop_filter_info.h = lerp(crop_filter_info.h, zoom_target.crop.h, ease_in_out(zoom_time))
            set_crop_settings(crop_filter_info)
            
            -- Calculate delta for blur
            dx = crop_filter_info.x - prev_x
            dy = crop_filter_info.y - prev_y

            -- Core fix: advance zoom animation time progress
            local frame_time = obs.obs_get_frame_interval_ns() / 1000000000
            zoom_time = zoom_time + zoom_speed * FRAME_TIME_SCALE * frame_time 
            -- END Core fix

        end
    else -- ZoomedIn or None (only follow/idle logic runs here)
        if is_following_mouse then
            zoom_target = get_target_position(zoom_info)

            local skip_frame = false
            if not use_follow_outside_bounds then
                if zoom_target.raw_center.x < zoom_target.crop.x or
                    zoom_target.raw_center.x > zoom_target.crop.x + zoom_target.crop.w or
                    zoom_target.raw_center.y < zoom_target.crop.y or
                    zoom_target.raw_center.y > zoom_target.crop.y + zoom_target.crop.h then
                    skip_frame = true
                end
            end

            if not skip_frame then
                if locked_center ~= nil then
                    local diff = {
                        x = zoom_target.raw_center.x - locked_center.x,
                        y = zoom_target.raw_center.y - locked_center.y
                    }
                    local track = {
                        x = zoom_target.crop.w * (0.5 - (follow_border * 0.01)),
                        y = zoom_target.crop.h * (0.5 - (follow_border * 0.01))
                    }
                    if math.abs(diff.x) > track.x or math.abs(diff.y) > track.y then
                        locked_center = nil
                        locked_last_pos = {
                            x = zoom_target.raw_center.x,
                            y = zoom_target.raw_center.y,
                            diff_x = diff.x,
                            diff_y = diff.y
                        }
                    end
                end

                if locked_center == nil and (zoom_target.crop.x ~= crop_filter_info.x or zoom_target.crop.y ~= crop_filter_info.y) then
                    
                    crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, follow_speed)
                    crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, follow_speed)
                    set_crop_settings(crop_filter_info)
                    
                    -- Calculate delta for blur
                    dx = crop_filter_info.x - prev_x
                    dy = crop_filter_info.y - prev_y


                    if is_following_mouse and locked_center == nil and locked_last_pos ~= nil then
                        local diff = {
                            x = math.abs(crop_filter_info.x - zoom_target.crop.x),
                            y = math.abs(crop_filter_info.y - zoom_target.crop.y),
                            auto_x = zoom_target.raw_center.x - locked_last_pos.x,
                            auto_y = zoom_target.raw_center.y - locked_last_pos.y
                        }
                        locked_last_pos.x = zoom_target.raw_center.x
                        locked_last_pos.y = zoom_target.raw_center.y

                        local lock = false
                        if math.abs(locked_last_pos.diff_x) > math.abs(locked_last_pos.diff_y) then
                            if (diff.auto_x < 0 and locked_last_pos.diff_x > 0) or (diff.auto_x > 0 and locked_last_pos.diff_x < 0) then
                                lock = true
                            end
                        else
                            if (diff.auto_y < 0 and locked_last_pos.diff_y > 0) or (diff.auto_y > 0 and locked_last_pos.diff_y < 0) then
                                lock = true
                            end
                        end

                        if (lock and use_follow_auto_lock) or (diff.x <= follow_safezone_sensitivity and diff.y <= follow_safezone_sensitivity) then
                            locked_center = {
                                x = math.floor(crop_filter_info.x + zoom_target.crop.w * 0.5),
                                y = math.floor(crop_filter_info.y + zoom_target.crop.h * 0.5)
                            }
                        end
                    end
                end
            end
        end
    end

    -- Motion Blur Logic
    if use_motion_blur and blur_filter and (dx ~= 0 or dy ~= 0) then
        -- 1. Calculate velocity (pixels per frame approx)
        local velocity = math.sqrt(dx*dx + dy*dy)
        
        -- 2. Apply blur based on velocity and strength
        local target_blur = velocity * motion_blur_strength
        
        -- Smooth threshold to prevent micro-jitter
        if target_blur < 0.05 then target_blur = 0 end 
        
        -- Optional: Cap max blur to prevent crazy artifacts during snaps
        if target_blur > 100 then target_blur = 100 end

        -- 3. Set Blur Intensity (Radius/Passes)
        set_blur_intensity(target_blur)
        
        -- 4. Apply Directional Blur Angle (if enabled and moving)
        if use_directional_blur and target_blur > 0.05 and blur_angle_param_name ~= "" and blur_filter_settings then
            
            -- Calculate the angle of movement vector (dx, dy) in radians
            -- atan2(dy, dx) gives angle from -pi to pi
            local angle_rad = math.atan2(-dy, dx)
            
            -- Convert to degrees: 0 to 360
            local angle_deg = angle_rad * (180 / math.pi)
            
            -- Normalize angle to 0-360 range
            angle_deg = (angle_deg % 360 + 360) % 360 
            
            -- Apply the angle
            obs.obs_data_set_double(blur_filter_settings, blur_angle_param_name, angle_deg)
            obs.obs_source_update(blur_filter, blur_filter_settings) 
            
            log("Directional Blur Angle: " .. string.format("%.2f", angle_deg) .. " degrees", 1)
        end
    else
        -- Ensure blur is reset if motion blur is enabled but there's no movement
        if use_motion_blur and blur_filter then
             set_blur_intensity(0)
             if blur_filter_settings and use_directional_blur and blur_angle_param_name ~= "" then
                obs.obs_data_set_double(blur_filter_settings, blur_angle_param_name, 0)
                obs.obs_source_update(blur_filter, blur_filter_settings)
            end
        end
    end

    if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
        if zoom_time >= 1 then
            local should_stop_timer = false
            if zoom_state == ZoomState.ZoomingOut then
                zoom_state = ZoomState.None
                should_stop_timer = true
                set_blur_intensity(0) -- Ensure blur is off when zoomed out
                if blur_filter_settings and use_directional_blur and blur_angle_param_name ~= "" then
                    obs.obs_data_set_double(blur_filter_settings, blur_angle_param_name, 0) -- Reset angle
                    obs.obs_source_update(blur_filter, blur_filter_settings)
                end
            elseif zoom_state == ZoomState.ZoomingIn then
                zoom_state = ZoomState.ZoomedIn
                should_stop_timer = (not use_auto_follow_mouse) and (not is_following_mouse)

                if use_auto_follow_mouse then
                    is_following_mouse = true
                end

                if is_following_mouse and follow_border < 50 then
                    zoom_target = get_target_position(zoom_info)
                    locked_center = { x = zoom_target.clamped_center.x, y = zoom_target.clamped_center.y }
                end
            end

            if should_stop_timer then
                is_timer_running = false
                obs.timer_remove(on_timer)
                set_blur_intensity(0) -- Stop blur when animation stops
                if blur_filter_settings and use_directional_blur and blur_angle_param_name ~= "" then
                    obs.obs_data_set_double(blur_filter_settings, blur_angle_param_name, 0) -- Reset angle
                    obs.obs_source_update(blur_filter, blur_filter_settings)
                end
            end
        end
    end
end

function on_socket_timer()
    if not socket_server then
        return
    end

    repeat
        local data, status = socket_server:receive_from()
        if data then
            local sx, sy = data:match("(-?%d+) (-?%d+)")
            if sx and sy then
                local x = tonumber(sx, 10)
                local y = tonumber(sy, 10)
                if not socket_mouse then
                    log("Socket server client connected")
                    socket_mouse = { x = x, y = y }
                else
                    socket_mouse.x = x
                    socket_mouse.y = y
                end
            end
        elseif status ~= "timeout" then
            error(status)
        end
    until data == nil
end

function start_server()
    if socket_available then
        local address = socket.find_first_address("*", socket_port)

        socket_server = socket.create("inet", "dgram", "udp")
        if socket_server ~= nil then
            socket_server:set_option("reuseaddr", 1)
            socket_server:set_blocking(false)
            socket_server:bind(address, socket_port)
            obs.timer_add(on_socket_timer, socket_poll)
            log("Socket server listening on port " .. socket_port .. "...")
        end
    end
end

function stop_server()
    if socket_server ~= nil then
        log("Socket server stopped")
        obs.timer_remove(on_socket_timer)
        socket_server:close()
        socket_server = nil
        socket_mouse = nil
    end
end

function set_crop_settings(crop)
    if crop_filter ~= nil and crop_filter_settings ~= nil then
        obs.obs_data_set_int(crop_filter_settings, "left", math.floor(crop.x))
        obs.obs_data_set_int(crop_filter_settings, "top", math.floor(crop.y))
        obs.obs_data_set_int(crop_filter_settings, "cx", math.floor(crop.w))
        obs.obs_data_set_int(crop_filter_settings, "cy", math.floor(crop.h))
        obs.obs_source_update(crop_filter, crop_filter_settings)
    end
end

function on_transition_start(t)
    log("Transition started")
    release_sceneitem()
end

function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        log("OBS Scene changed")
        if is_obs_loaded then
            refresh_sceneitem(true)
        end
    elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        log("OBS Loaded")
        is_obs_loaded = true
        monitor_info = get_monitor_info(source)
        refresh_sceneitem(true)
    elseif event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
        log("OBS Shutting down")
        if is_script_loaded then
            script_unload()
        end
    end
end

function on_update_transform()
    if is_obs_loaded then
        refresh_sceneitem(true)
    end
    return true
end

function on_settings_modified(props, prop, settings)
    local name = obs.obs_property_name(prop)

    if name == "use_monitor_override" then
        local visible = obs.obs_data_get_bool(settings, "use_monitor_override")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_label"), not visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_w"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_h"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sx"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sy"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dw"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dh"), visible)
        return true
    elseif name == "use_socket" then
        local visible = obs.obs_data_get_bool(settings, "use_socket")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_label"), not visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_port"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_poll"), visible)
        return true
	elseif name == "use_motion_blur" then
        local visible = obs.obs_data_get_bool(settings, "use_motion_blur")
        -- Core fix: use more compatible way to handle group properties
        if visible then
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_info"), true)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_filter_name"), true)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_strength"), true)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_param_name"), true)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "use_directional_blur"), true)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "blur_angle_param_name"), true)
        else
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_info"), false)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_filter_name"), false)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_strength"), false)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "motion_blur_param_name"), false)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "use_directional_blur"), false)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "blur_angle_param_name"), false)
        end
        return true
    elseif name == "allow_all_sources" then
        local sources_list = obs.obs_properties_get(props, "source")
        populate_zoom_sources(sources_list)
        return true
    elseif name == "debug_logs" then
        if obs.obs_data_get_bool(settings, "debug_logs") then
            log_current_settings()
        end
    end

    return false
end

function log_current_settings()
    local settings = {
        zoom_value = zoom_value,
        zoom_speed = zoom_speed,
        use_auto_follow_mouse = use_auto_follow_mouse,
        use_motion_blur = use_motion_blur,
        motion_blur_strength = motion_blur_strength,
        use_directional_blur = use_directional_blur, -- NEW
        debug_logs = debug_logs,
        version = VERSION
    }
    log("Current settings:\n" .. format_table(settings))
end

function on_print_help()
    obs.script_log(obs.OBS_LOG_INFO, "See script source for full help.")
end

function script_description()
    return "Zoom the selected display-capture source to focus on the mouse.\nModified with Motion Blur support, including directional blur."
end

function script_properties()
    local props = obs.obs_properties_create()

    local sources_list = obs.obs_properties_add_list(props, "source", "Zoom Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_zoom_sources(sources_list)

    obs.obs_properties_add_button(props, "refresh", "Refresh zoom sources", function()
        populate_zoom_sources(sources_list)
        monitor_info = get_monitor_info(source)
        -- Fixes an issue where filter reference might not be updated on refresh
        refresh_sceneitem(true) 
        return true
    end)
    
    obs.obs_properties_add_bool(props, "allow_all_sources", "Allow any zoom source ")

    obs.obs_properties_add_float(props, "zoom_value", "Zoom Factor", 1, 5, 0.5)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.01, 1, 0.01)
    obs.obs_properties_add_bool(props, "follow", "Auto follow mouse ")

    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.01, 1, 0.01)
    obs.obs_properties_add_int_slider(props, "follow_border", "Follow Border", 0, 50, 1)
    obs.obs_properties_add_int_slider(props, "follow_safezone_sensitivity", "Lock Sensitivity", 1, 20, 1)
    obs.obs_properties_add_bool(props, "follow_outside_bounds", "Follow outside bounds ")
    obs.obs_properties_add_bool(props, "follow_auto_lock", "Auto Lock on reverse direction ")
    
    -- Motion Blur Settings Group
    local blur_group_props = obs.obs_properties_create()

    local use_blur = obs.obs_properties_add_bool(blur_group_props, "use_motion_blur", "Enable Motion Blur Control")
    obs.obs_property_set_long_description(use_blur, "Enables controlling an existing Blur filter based on movement speed.")
    
    local blur_info = obs.obs_properties_add_text(blur_group_props, "motion_blur_info", 
        "NOTE: You must add a Blur Filter (e.g. Composite Blur) to the source manually!", 
        obs.OBS_TEXT_INFO)
    
    local blur_name = obs.obs_properties_add_text(blur_group_props, "motion_blur_filter_name", "Blur Filter Name", obs.OBS_TEXT_DEFAULT)
    local blur_strength = obs.obs_properties_add_float_slider(blur_group_props, "motion_blur_strength", "Blur Strength", 0.0, 10.0, 0.01)
    local blur_param = obs.obs_properties_add_text(blur_group_props, "motion_blur_param_name", "Blur Parameter Name (e.g. radius/kawase_passes)", obs.OBS_TEXT_DEFAULT)

    -- NEW Directional Blur Controls
    local use_dir_blur = obs.obs_properties_add_bool(blur_group_props, "use_directional_blur", "Enable Directional Blur (Box/Motion)")
    obs.obs_property_set_long_description(use_dir_blur, "Use with Composite Blur's 'Box' algorithm. It sets the blur angle to match the movement vector.")
    local blur_angle_param = obs.obs_properties_add_text(blur_group_props, "blur_angle_param_name", "Blur Angle Parameter Name (e.g. angle)", obs.OBS_TEXT_DEFAULT)

    -- Add the properties group to the main properties object
    local blur_group_handle = obs.obs_properties_add_group(props, "motion_blur_group", "Motion Blur Settings", obs.OBS_GROUP_NORMAL, blur_group_props)
    
    obs.obs_property_set_modified_callback(use_blur, on_settings_modified)
    
    -- Initialize visibility (references are still correct inside the sub-properties object)
    local visible = use_motion_blur
    obs.obs_property_set_visible(blur_info, visible)
    obs.obs_property_set_visible(blur_name, visible)
    obs.obs_property_set_visible(blur_strength, visible)
    obs.obs_property_set_visible(blur_param, visible)
    obs.obs_property_set_visible(use_dir_blur, visible)
    obs.obs_property_set_visible(blur_angle_param, visible)

    local override_props = obs.obs_properties_create();
    local override_label = obs.obs_properties_add_text(override_props, "monitor_override_label", "", obs.OBS_TEXT_INFO)
    local override_x = obs.obs_properties_add_int(override_props, "monitor_override_x", "X", -10000, 10000, 1)
    local override_y = obs.obs_properties_add_int(override_props, "monitor_override_y", "Y", -10000, 10000, 1)
    local override_w = obs.obs_properties_add_int(override_props, "monitor_override_w", "Width", 0, 10000, 1)
    local override_h = obs.obs_properties_add_int(override_props, "monitor_override_h", "Height", 0, 10000, 1)
    local override_sx = obs.obs_properties_add_float(override_props, "monitor_override_sx", "Scale X ", 0, 100, 0.01)
    local override_sy = obs.obs_properties_add_float(override_props, "monitor_override_sy", "Scale Y ", 0, 100, 0.01)
    local override_dw = obs.obs_properties_add_int(override_props, "monitor_override_dw", "Monitor Width ", 0, 10000, 1)
    local override_dh = obs.obs_properties_add_int(override_props, "monitor_override_dh", "Monitor Height ", 0, 10000, 1)
    local override = obs.obs_properties_add_group(props, "use_monitor_override", "Set manual source position ", obs.OBS_GROUP_CHECKABLE, override_props)
    obs.obs_property_set_modified_callback(override, on_settings_modified)
    
    -- Core fix: set visibility controlling
    local visible = use_monitor_override
    obs.obs_property_set_visible(override_label, not visible)
    obs.obs_property_set_visible(override_x, visible)
    obs.obs_property_set_visible(override_y, visible)
    obs.obs_property_set_visible(override_w, visible)
    obs.obs_property_set_visible(override_h, visible)
    obs.obs_property_set_visible(override_sx, visible)
    obs.obs_property_set_visible(override_sy, visible)
    obs.obs_property_set_visible(override_dw, visible)
    obs.obs_property_set_visible(override_dh, visible)

    if socket_available then
        local socket_props = obs.obs_properties_create();
        local socket_label = obs.obs_properties_add_text(socket_props, "socket_label", "", obs.OBS_TEXT_INFO)
        local socket_port = obs.obs_properties_add_int(socket_props, "socket_port", "Port ", 1024, 65535, 1)
        local socket_poll = obs.obs_properties_add_int(socket_props, "socket_poll", "Poll Delay (ms) ", 0, 1000, 1)
        local socket = obs.obs_properties_add_group(props, "use_socket", "Enable remote mouse listener ", obs.OBS_GROUP_CHECKABLE, socket_props)
        obs.obs_property_set_modified_callback(socket, on_settings_modified)
        
        -- Core fix: set visibility controlling
        local visible = use_socket
        obs.obs_property_set_visible(socket_label, not visible)
        obs.obs_property_set_visible(socket_port, visible)
        obs.obs_property_set_visible(socket_poll, visible)
    end

    local help = obs.obs_properties_add_button(props, "help_button", "More Info", on_print_help)
    local debug = obs.obs_properties_add_bool(props, "debug_logs", "Enable debug logging ")
    obs.obs_property_set_modified_callback(debug, on_settings_modified)

    return props
end

function script_load(settings)
    sceneitem_info_orig = nil
    local current_scene = obs.obs_frontend_get_current_scene()
    is_obs_loaded = current_scene ~= nil
    obs.obs_source_release(current_scene)

    hotkey_zoom_id = obs.obs_hotkey_register_frontend("toggle_zoom_hotkey", "Toggle zoom to mouse", on_toggle_zoom)
    hotkey_follow_id = obs.obs_hotkey_register_frontend("toggle_follow_hotkey", "Toggle follow mouse during zoom", on_toggle_follow)

    local hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.zoom")
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.follow")
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    
    use_socket = obs.obs_data_get_bool(settings, "use_socket")
    socket_port = obs.obs_data_get_int(settings, "socket_port")
    socket_poll = obs.obs_data_get_int(settings, "socket_poll")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    -- Load Blur Settings
    use_motion_blur = obs.obs_data_get_bool(settings, "use_motion_blur")
    motion_blur_strength = obs.obs_data_get_double(settings, "motion_blur_strength")
    motion_blur_filter_name = obs.obs_data_get_string(settings, "motion_blur_filter_name")
    motion_blur_param_name = obs.obs_data_get_string(settings, "motion_blur_param_name")
    
    -- Load Directional Blur Settings (NEW)
    use_directional_blur = obs.obs_data_get_bool(settings, "use_directional_blur")
    blur_angle_param_name = obs.obs_data_get_string(settings, "blur_angle_param_name")


    obs.obs_frontend_add_event_callback(on_frontend_event)

    if debug_logs then log_current_settings() end

    local transitions = obs.obs_frontend_get_transitions()
    if transitions ~= nil then
        for i, s in pairs(transitions) do
            local handler = obs.obs_source_get_signal_handler(s)
            obs.signal_handler_connect(handler, "transition_start", on_transition_start)
        end
        obs.source_list_release(transitions)
    end

    if ffi.os == "Linux" and not x11_display then
        log("ERROR: Could not get X11 Display for Linux")
    end

    source_name = ""
    use_socket = false
    is_script_loaded = true
end

function script_unload()
    is_script_loaded = false
    if version_number > 2901 or (version_number == 2901 and patch > 2) then
        local transitions = obs.obs_frontend_get_transitions()
        if transitions ~= nil then
            for i, s in pairs(transitions) do
                local handler = obs.obs_source_get_signal_handler(s)
                obs.signal_handler_disconnect(handler, "transition_start", on_transition_start)
            end
            obs.source_list_release(transitions)
        end
        obs.obs_hotkey_unregister(on_toggle_zoom)
        obs.obs_hotkey_unregister(on_toggle_follow)
        obs.obs_frontend_remove_event_callback(on_frontend_event)
        release_sceneitem()
    end
    if x11_lib ~= nil and x11_display ~= nil then
        x11_lib.XCloseDisplay(x11_display)
        x11_display = nil
        x11_lib = nil
    end
    if socket_server ~= nil then stop_server() end
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.06)
    obs.obs_data_set_default_bool(settings, "follow", true)
    obs.obs_data_set_default_bool(settings, "follow_outside_bounds", false)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.25)
    obs.obs_data_set_default_int(settings, "follow_border", 8)
    obs.obs_data_set_default_int(settings, "follow_safezone_sensitivity", 4)
    obs.obs_data_set_default_bool(settings, "follow_auto_lock", false)
    obs.obs_data_set_default_bool(settings, "allow_all_sources", false)
    obs.obs_data_set_default_bool(settings, "use_monitor_override", false)
    
    -- Blur Defaults
    obs.obs_data_set_default_bool(settings, "use_motion_blur", false)
    obs.obs_data_set_default_double(settings, "motion_blur_strength", 1.0)
    obs.obs_data_set_default_string(settings, "motion_blur_filter_name", "Motion Blur")
    obs.obs_data_set_default_string(settings, "motion_blur_param_name", "Size")

    -- Directional Blur Defaults (NEW)
    obs.obs_data_set_default_bool(settings, "use_directional_blur", false)
    obs.obs_data_set_default_string(settings, "blur_angle_param_name", "angle")

    obs.obs_data_set_default_int(settings, "monitor_override_x", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_y", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_w", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_h", 1080)
    obs.obs_data_set_default_double(settings, "monitor_override_sx", 1)
    obs.obs_data_set_default_double(settings, "monitor_override_sy", 1)
    obs.obs_data_set_default_int(settings, "monitor_override_dw", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_dh", 1080)
    obs.obs_data_set_default_bool(settings, "use_socket", false)
    obs.obs_data_set_default_int(settings, "socket_port", 12345)
    obs.obs_data_set_default_int(settings, "socket_poll", 10)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
end

function script_save(settings)
    if hotkey_zoom_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.zoom", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
    if hotkey_follow_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.follow", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
end

function script_update(settings)
    local old_source_name = source_name
    local old_override = use_monitor_override
    local old_x = monitor_override_x
    local old_y = monitor_override_y
    local old_w = monitor_override_w
    local old_h = monitor_override_h
    local old_sx = monitor_override_sx
    local old_sy = monitor_override_sy
    local old_dw = monitor_override_dw
    local old_dh = monitor_override_dh
    local old_socket = use_socket
    local old_port = socket_port
    local old_poll = socket_poll
    
    -- Check blur changes
    local old_blur_use = use_motion_blur
    local old_blur_name = motion_blur_filter_name
    local old_dir_blur_use = use_directional_blur 

    source_name = obs.obs_data_get_string(settings, "source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    
    use_motion_blur = obs.obs_data_get_bool(settings, "use_motion_blur")
    motion_blur_strength = obs.obs_data_get_double(settings, "motion_blur_strength")
    motion_blur_filter_name = obs.obs_data_get_string(settings, "motion_blur_filter_name")
    motion_blur_param_name = obs.obs_data_get_string(settings, "motion_blur_param_name")
    
    use_directional_blur = obs.obs_data_get_bool(settings, "use_directional_blur") 
    blur_angle_param_name = obs.obs_data_get_string(settings, "blur_angle_param_name") 

    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    use_socket = obs.obs_data_get_bool(settings, "use_socket")
    socket_port = obs.obs_data_get_int(settings, "socket_port")
    socket_poll = obs.obs_data_get_int(settings, "socket_poll")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    local blur_changed = (old_blur_use ~= use_motion_blur) or (old_blur_name ~= motion_blur_filter_name) or (old_dir_blur_use ~= use_directional_blur) 

    if (source_name ~= old_source_name or blur_changed) and is_obs_loaded then
        refresh_sceneitem(true)
    end

    if source_name ~= old_source_name or
        use_monitor_override ~= old_override or
        monitor_override_x ~= old_x or
        monitor_override_y ~= old_y or
        monitor_override_w ~= old_w or
        monitor_override_h ~= old_h or
        monitor_override_sx ~= old_sx or
        monitor_override_sy ~= old_sy or
        monitor_override_w ~= old_dw or
        monitor_override_h ~= old_dh then
        if is_obs_loaded then
            monitor_info = get_monitor_info(source)
        end
    end

    if old_socket ~= use_socket then
        if use_socket then start_server() else stop_server() end
    elseif use_socket and (old_poll ~= socket_poll or old_port ~= socket_port) then
        stop_server()
        start_server()
    end
end

function populate_zoom_sources(list)
    obs.obs_property_list_clear(list)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        local dc_info = get_dc_info()
        obs.obs_property_list_add_string(list, "<None>", "obs-zoom-to-mouse-none")
        for _, source in ipairs(sources) do
            local source_type = obs.obs_source_get_id(source)
            if source_type == dc_info.source_id or allow_all_sources then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(list, name, name)
            end
        end
        obs.source_list_release(sources)
    end
end