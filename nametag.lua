local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer

-- re-executing: cleanly unload the previous copy first (restores the tag it hid)
local env = (getgenv and getgenv()) or _G
pcall(function() if env.c1lownUnload then env.c1lownUnload() end end)

local GUI_NAME = "c1lownNametagGui"
pcall(function()
    local old = (gethui and gethui() or CoreGui):FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okp = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not okp or not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

local connections = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(connections, c)
    return c
end

-- Online profiles are read from this GitHub folder (raw link, must end in /).
-- Edit a file in the repo and everyone running the script sees it within minutes.
local PROFILE_URL = "https://raw.githubusercontent.com/C1lown/C1own_Nametag/main/profiles/"

local DEFAULT = {
    title = lp.DisplayName, sub = "@" .. lp.Name, icon = "",
    enabled = true, hideDefault = true,
    hideForeign = true, -- hide other overhead tags on your character (e.g. "AK USER")
    matchForeign = true, -- copy the hidden tag's size, height and anchor so yours takes its exact place
    followForeign = true, -- your tag turns on/off with the other script's nametag button
    matchScale = 100, -- % resize applied on top of the copied size
    matchHeight = 0, -- extra height (tenths of a stud) on top of the copied position
    font = "GothamBold", subFont = "Gotham",
    titleColor = "FFFFFF", subColor = "C9C2FF", titleStroke = true,

    bg1 = "1E1C2C", bg2 = "0A0A0F", bgRot = 60, bgAlpha = 4, bgSpin = false,
    corner = 22,

    outline = true, ol1 = "7C66FF", ol2 = "4896FF", olThick = 2, olSpin = true, rainbow = false,

    glow = true, glowColor = "7C66FF", glowAlpha = 55, pulse = true,

    iconCorner = 18, iconRing = true, iconRingColor = "7C66FF",

    size = 4, widthPct = 100, offset = 0, maxDist = 300, onTop = true,

    beacon = true, notify = false,
    menuKey = "RightAlt",
    showOthers = true, -- show other script users' tags
    autoProfiles = true, -- create a template profile file for every player in the server
    decor = false, -- decorative images on the tag (emo theme)
    zoomScale = 60, -- 0 = normal world size, 100 = same size on screen at any zoom
}
local cfg = {}
for k, v in pairs(DEFAULT) do cfg[k] = v end

local SAVE_FILE = "c1lown_nametag.json"
local function loadSaved()
    if not (isfile and readfile and isfile(SAVE_FILE)) then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SAVE_FILE)) end)
    if not ok or type(data) ~= "table" then return false end
    for k, v in pairs(data) do
        if DEFAULT[k] ~= nil and type(v) == type(DEFAULT[k]) then cfg[k] = v end
    end
    return true
end
local function saveConfig()
    if not writefile then return false end
    return (pcall(writefile, SAVE_FILE, HttpService:JSONEncode(cfg)))
end
loadSaved()

-- ====================================================================
-- Profile folder (executor workspace/c1lown_nametag)
--   profiles/<username>.json   one file per player, see README.txt
--   <image files>              PNG/JPG next to the README, referenced by name
-- Anyone with a profile gets that tag on YOUR screen, script user or not.
-- ====================================================================
local FOLDER = "c1lown_nametag"
local PROFILES = FOLDER .. "/profiles"

pcall(function()
    if not (makefolder and isfolder) then return end
    if not isfolder(FOLDER) then makefolder(FOLDER) end
    if not isfolder(PROFILES) then makefolder(PROFILES) end
    if writefile and isfile then
        if not isfile(FOLDER .. "/README.txt") then
            writefile(FOLDER .. "/README.txt", [[
c1lown nametag profiles

Put one file per player in the "profiles" folder, named after their Roblox
username or display name:   profiles/TheyluvJayden543.json

Example:
{
  "title": "cut4law",
  "sub": "@TheyluvJayden543",
  "icon": "cut4law.png",
  "bg1": "1A1A24", "bg2": "0A0A0F",
  "ol1": "C9C2FF", "ol2": "7C66FF",
  "glowColor": "7C66FF",
  "iconCorner": 50
}

"icon" can be an image ID, or a PNG/JPG file placed in this folder
(c1lown_nametag/cut4law.png). Any setting from the menu can be used as a key
(title, sub, font, titleColor, subColor, bg1, bg2, ol1, ol2, glowColor, size...).
Colours are 6-digit hex without the #.

Template files are created automatically for everyone in the server, with
"active": false. They do nothing until you edit them and set "active": true
(or delete that line).

A profile for YOUR OWN username changes your own tag.
Online profiles (GitHub) are used when you have no active local file.
Press "Reload profiles" in the Players tab after adding or editing files.
]])
        end
        if not isfile(PROFILES .. "/_example.json") then
            writefile(PROFILES .. "/_example.json", '{"title":"Example","sub":"@username","icon":"","bg1":"1A1A24","bg2":"0A0A0F","ol1":"C9C2FF","ol2":"7C66FF"}')
        end
    end
end)

local warned = {}
local function warnOnce(key, msg)
    if warned[key] ~= msg then
        warned[key] = msg
        print(msg)
    end
end

-- online profiles (GitHub raw) ------------------------------------------
local remote, remoteRaw = {}, {}

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return true, body end
    if not ok and tostring(body):find("404", 1, true) then return false, "404 not found" end
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        local ok2, res = pcall(req, { Url = url, Method = "GET" })
        if ok2 and type(res) == "table" then
            local code = res.StatusCode or res.Status
            if (code == 200 or res.Success == true) and type(res.Body) == "string" then return true, res.Body end
            return false, "HTTP " .. tostring(code)
        end
        return false, tostring(res)
    end
    return false, tostring(body)
end

local function fetchRemoteFor(plr)
    local base = PROFILE_URL
    local key = plr.Name:lower()
    if type(base) ~= "string" or base == "" then remote[key], remoteRaw[key] = nil, nil return end
    if base:sub(-1) ~= "/" then base = base .. "/" end
    local ok, body = httpGet(base .. plr.Name .. ".json")
    if not ok or type(body) ~= "string" then remote[key], remoteRaw[key] = nil, nil return end
    local okd, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not (okd and type(data) == "table") then remote[key], remoteRaw[key] = nil, nil return end
    -- icon file in the repo: download it into the workspace folder once
    local ic = data.icon
    if type(ic) == "string" and ic:match("^[%w_%-]+%.[pPjJ][nNpP][gGeE]?[gG]?$") and writefile and isfile then
        local path = FOLDER .. "/" .. ic
        if not isfile(path) then
            local oki, img = httpGet(base .. ic)
            if oki and type(img) == "string" and #img > 0 then pcall(writefile, path, img) end
        end
    end
    remote[key], remoteRaw[key] = data, body
end

local function readProfile(plr)
    if isfile and readfile then
        for _, key in ipairs({ plr.Name, plr.Name:lower(), plr.DisplayName, plr.DisplayName:lower() }) do
            local path = PROFILES .. "/" .. key .. ".json"
            local okf, exists = pcall(isfile, path)
            if okf and exists then
                local okd, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
                if okd and type(data) == "table" then
                    if data.active == false then
                        warnOnce(path, "[nametag] " .. path .. " is ignored: \"active\" is false")
                        break -- fall through to the online profile
                    end
                    return data
                else
                    warnOnce(path, "[nametag] " .. path .. " isn't valid JSON (check commas and quotes): " .. tostring(data))
                end
            end
        end
    end
    local r = remote[plr.Name:lower()]
    if r and r.active ~= false then return r end
    return nil
end

-- profiles can change how a tag looks, never your private settings
local BLOCKED = { menuKey = true, beacon = true, notify = true,
    showOthers = true, autoProfiles = true, hideForeign = true, hideDefault = true,
    matchForeign = true, followForeign = true, enabled = true }
local function mergeProfile(dst, prof)
    for k, v in pairs(prof) do
        if DEFAULT[k] ~= nil and not BLOCKED[k] and type(v) == type(DEFAULT[k]) then dst[k] = v end
    end
end

-- Auto-create a template profile for a player if none exists yet. Templates
-- start with "active": false so they do nothing until you edit the file and
-- set "active": true (or delete that line).
local function jsonStr(s) return '"' .. tostring(s):gsub('[\\"]', '\\%0') .. '"' end
local function ensureProfileFile(plr)
    if not (cfg.autoProfiles and writefile and isfile) then return end
    for _, key in ipairs({ plr.Name, plr.Name:lower(), plr.DisplayName, plr.DisplayName:lower() }) do
        local okf, exists = pcall(isfile, PROFILES .. "/" .. key .. ".json")
        if okf and exists then return end
    end
    local body = table.concat({
        "{",
        '  "active": false,',
        '  "title": ' .. jsonStr(plr.DisplayName) .. ",",
        '  "sub": ' .. jsonStr("@" .. plr.Name) .. ",",
        '  "icon": "",',
        '  "bg1": "1E1C2C", "bg2": "0A0A0F",',
        '  "ol1": "7C66FF", "ol2": "4896FF",',
        '  "glowColor": "7C66FF"',
        "}",
    }, "\n")
    pcall(writefile, PROFILES .. "/" .. plr.Name .. ".json", body)
end

-- image id / rbxthumb / file inside the folder (or anywhere in the workspace)
local function resolveAsset(src)
    src = (tostring(src or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if src == "" then return nil end
    local id = src:match("^(%d+)$") or src:match("^rbxassetid://(%d+)$") or src:match("[?&]id=(%d+)")
    if id then return "rbxassetid://" .. id end
    if src:match("^rbxthumb://") or src:match("^rbxasset://") then return src end
    if not (isfile and getcustomasset) then return nil end
    for _, path in ipairs({ FOLDER .. "/" .. src, src }) do
        local okf, exists = pcall(isfile, path)
        if okf and exists then
            local oka, asset = pcall(getcustomasset, path)
            if oka then return asset end
        end
    end
    return nil
end

-- Owner tag: if the account running the script is C1lown3, the avatar-theme tag
-- (white + gold, with images) is applied automatically, no button. Other players keep
-- the default style.
local OWNER_NAME = "c1lown3"
local EMO_PRESET = {
    title = "C1lown3", sub = "i'm fine :)",
    font = "GothamBold", subFont = "Gotham",
    titleColor = "26262B", subColor = "9A7B1C", titleStroke = false,
    bg1 = "FFFFFF", bg2 = "E4DED2", bgRot = 90, bgAlpha = 4, bgSpin = false,
    corner = 22, size = 3,
    outline = true, ol1 = "F6C440", ol2 = "FFFFFF", olThick = 2, olSpin = true, rainbow = false,
    glow = true, glowColor = "FFD76A", glowAlpha = 55, pulse = true,
    iconCorner = 50, iconRing = false, iconRingColor = "F6C440",
}

-- Embedded theme artwork (small PNGs, base64). On load they are written to the
-- executor workspace and loaded with getcustomasset, so nothing is downloaded.
local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64MAP = {}
for i = 1, #B64CHARS do B64MAP[B64CHARS:sub(i, i)] = i - 1 end
local function b64decode(s)
    local out, bits, nbits = {}, 0, 0
    for i = 1, #s do
        local v = B64MAP[s:sub(i, i)]
        if v then
            bits = bits * 64 + v
            nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                local p = 2 ^ nbits
                out[#out + 1] = string.char(math.floor(bits / p))
                bits = bits % p
            end
        end
    end
    return table.concat(out)
end

local EMO_ART = {
    icon = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAMAAADVRocKAAAAkFBMVEUuJh3l3sz/4obVsEz+4Xi5iCDKmSf50mv//////wD/f3+ibgnv0nH24KOppZ3+5Yj+4H5nYFj/AADMoT3/34BJQjlDPDP/sGL/fwCCe3L/AP+LhX3/qqr+4YIAAAD2xECqdg3++/H0wjz623z83oD/8pXptje2ghb+4YH//34zKyL/4oHXpSzFmDLKlyPnyGcF9BQ1AAAAMHRSTlP//ySeGdTv/wEBAv6C//9Vav8BrYH//wQC/wH/A3cA//3//3p4bv/2gAL/Uf+6/4gfOqHqAAAHZklEQVR42rUaiXbqOAx1jKEJO3R7b2achDiEpC7w/3838hKvAVpafHraNIuutViSJaP8xpim8ItggvmamsE5wRjDg6xLb3yPrj3cSuqYrHhPuZY/lM4ljMTYptmdAFkn576itLVzZ8xety1dYwIvXWPjMgB81JEV9Ue93zPvxhz4AIzu2wB/QDSYu3OH2dP5+DgajygLYAVE+i2AdJq/Ey1uB2B/LGGMI4CW4i5P068DAMNk1QZUgOy5lGO0DxFoy/A0n34VYJpjTuPB6FgBHCLeBATH+ZA9xQDwFqbtAP39qCwvsiDllA8wgWLj6VaUrVk4R/j/UJazz88ZILCIhZox1q6IMI7rAF1OeAtf72kAoRmoCoApjwELNYMPgImaRNYUAJCcgMLoaHxke29R1ZQJ+p9FMRF/z64lwXt7dgTzBWeC8/+uAcD8KbwmreV4ljPzTPRQFAphbFkQnJ6PBpUEiw5F9K02JyP9vTHRpqiqopF6VizIGYwmju5fiG9MyJMPVsSMuQDbSlLKRCdFVcDPaSZWW61kA+I0xiVBX3weHABhnrW7oBSEUsZIMyBk1OjpCtFb8kYxLXatFbnLq9fnXIj786C/O8730kTLk6IPLKjVtp8f9Svq5XlvvDjPYoC0py8gDlKfDsSzMtF+iAfPDnl552DtGlspIRNbOt4akxxLeYAwJlYAYKIaoSo+nduTRkttTF2EbQDQ5Ya+1qi0mKI5lTM9z8IZmrdZeQLy2rIcL9ty41tRTx9bD8boUZuMhigdDSsWGnVPk6/k2jg6i681QkLagIjnFZ6NRAREJZRxKrxxEqKv1HMts2fPf/ROA2kPyt24K43yZEUOq7cpgtFM9CNjV36k42RqAVKPgRCgsBf+cJ7HAP1qkADZO/c987lftoZEhOHeUTo4Bz4cb3sAcEGtDzAPrebW8NZZb0mSBQDIMhLGFrnSqq/Tr9Q68zmo8XYqATpnDffBq19poVjUiB6oZRAAAAudBPiHWA3UtYh9dDWJASThJxj6MgSYQKRlDAi4ppoBgHFyTDwHFwbe8zyOtfy0SJKdHEmyeIp1PD4z8a2Mzqw3pBQA0py/iLs97dFxHPgeSV4T70fiQBjfBHmfRQF663cpIiIsX9CeA+2DcWIzC9CE5BVEYwFm5rMDoMwVPeHzpkiFSTtvM052+ovd4FhYJk7Bx4IXILvKOzTNV3N69B8fTp9NYwVwgT4gWCE2zefp4FMB51d3W5RjnZGU0i97tBX9ZHdxJL4X6VG0wCA9w6ADbJJOS9uxw2qxuzIWlWfFPYoSE61bAgBrcBNMIjRPAXEREa7SlwhVEYA8yWgxZnTd8g5hPhd5xCGIKf0nT7sb4yn6REWjg8oxCNKp0AWEylVAYoZ7s7pGvwaA2kltD5WP4DOwRB8w0AdaXmahko7PZvgYYTfIhAgeA7t/Efp4e/1AaLO7xIKh3wcfjlZ+ej5x45fPQIJgbP4CClpcYKHSybfdoXDEaYRQDJposgHKaJmAnNBrMmiqRUSf1ihMJmYny4OVULIU8kHoLdltxMXH32USyQj+irzYTy+QF+yPpZ9OJI54evUKScE1SqLlrGK/lx/5ADXbT1w3WhVWPh9CAcp8pC7Qh5WSeV061cne23whP19RTkMjODpOxJzflkYbwEMSaFlHhTH19+loKBrreO8BvG2s1HfLzVsEoAw0iswBgBJSOQDwunEsJ1m+ohigjAUUikipeXZBRD2EEBEaEtFMqfiyiNRWcnYyZucpubec5FVcxkrWRhrsoVG8154MxBplphIB6F8w03iZ+QCxs3AXmlxfwgtJE0Kb4YUWIxhfZByqmzW7rmLxalyF708XbhZ+CBGMLxpy2IGzk4peoiv+OnTWAuAb7vrvHe561QccvflubgYcdCvgNO6mHAIOqR8aMgFA0mflbwd9yIqYjMmPTFsgoHUItk/rRyVeDPYgkNmtH5c6QnqNphl/XPILexxI33H7sPQdNppoK3ZQj9uAdGKfzOmDtlAgIVDyn0duAju5je3ow7axU70Rbx+zEc/URjx9VCmB6J2+ZGH9iGJIZwpSmD6inCOLm7og5WnhdwpSXNXUVEEqJb9dUltTnKZOzU5XlX+tKMhoX182ZU2n6PUbZU3ulzUFD+tfLMzCGkuj4jhxrOjHpWViyuPINiceWxx3EH5c3peVroEGRb8aftqgeOFuC8Rtsbzn5OXnLZaWTy/1cLJUIvyoSSQKLNv0SpsLG2L3tblaTv7ZXmnUdaIAVt/bqFMebnu11SiqqPe2GmUjMMtuNEtFr7dl9PvN0pq1NG5lDrR7p2F4+GK7F/YC7wO9/YGGNTCJ+cu3G9YiR/nz5ZZ7N9CzvtpyX3MyfG5g+NAAiInwCOLioYEXyvGlow/o8qmKCEKb6jkAaBX57JsHN7biaALxToWonZYXGesXdaqiy+44epJ28uRJXbdOKGLWQmsBviIw+2x65+EZ+aE4mGMmzWw1qBZndOTJlnsPzxg28o5gzP1OGMcYi0fT6Q0C/wNXuSFIcQyPXQAAAABJRU5ErkJggg==",
    spark = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAMAAADVRocKAAAAkFBMVEXfWgClcRi/PwD/vwDEkB/87cQAAACteA73xUH0wj24gxT++/G2ewOibgnquDiveQ7//wCveQ6rdg2sdw3LmCN/fwCpVQCtdw7YpSypdA6qqgD/AACYZwP/fwDhrjKnaxLBjR340Wr/qgCjbQtVVQB/PwCZWwDMmQD75q2dawr624v98tYA/wB/AAB/VQCZTACR5TQ+AAAAMHRSTlMEDwQE//8A/P///v8J/P/SAa9Nb/4CA5D/MAMBCgL/E///Ay4DBAgF/yP//wECBgoJJO0nAAAEP0lEQVR42r1aWXujOBAke0igCBBgcQh8xbk2yc7+/3+33TqAJJ58MENHD37Atkpd1arWQcSIW7Tu59qYPSkAcQSKXcqy03QAd6wQIh/eeiIAxYaCc37DNBGAZv9A/7xjhiyCDgFKVhMB1KxCgIYQoEGA4l9FlUX3OQLwgShNFbux/YPKmgRAo8ZCoMqGBOAPVvL0r13KKyZJACRrRLprU16sSaNolVHwtM04z2vdEwD0TEISZQgg2T0BQG3ncRZblSUBgASNuYjjEweVBxKACjSO410qGvYnCUWN4G0ct2AW96rfHKBX/0ExOMQxqjwwtTmAssUgi+NknVksBjDWKGJo68xiBQAk0QkCQJWr5XM5WqMxJFGSxGAWDYEGvTUKBECVHwjSdECjAIYQgMvFIUSLkwiNIom9ysvTKFqhcWqTKHFmITcGgGLAUWOXRqCy3DwCpzEC2JpjtgVQ/U3Q2KXRcakI0dJZcHFGgQ3T6LJ0qkUr5rGIfbNmsW0ET7BqdBpj23Ewi6dNAWwStQ4AVYaac7clgNKPUAxGgAPUnLpXGwH02gySHUMSTWkkB7Ng+fI1gKqldmI6jT2AU9kuJ7Ws1a8A9GofhQ2r7KqmyGdJZAHyoqk6P533Jtr/rEpHVyiRg3R9P8qyanLsGzIfVxTg1glGAWZhH+Z5U5Xy0aHA365Q9h5A11JaSgbZlVXhtgOuiV2CxeB8xs9kJ2Zf5UVVdtIulbSUtb4G0OvaGEfmGw678MPmdqi7Nsss+c+30J6tFFnWWpSU+2AKDObNSWfMuHxFABlJ5dnGYc/6Fifo288u6PbvW9te4/ERoJzEDMUF41CgWweAnf8YPCVioqQ9ZEFUy3zyfOvbc+IfeW86tBNlwlM2/LBlykbgKbGjxmGLadjI9xjA7djO08OAg8Hg9idNgzBAGUZwB0vOmZLAdjIb9awl5wng5cNXE0o2CwYd6y7Cfcv45AS0TP2vARgRDu1pAoDCBxQdJ4YcRbsZzMjQdYqmHyReiUCR5egY0nQ4fkr7kJvTCCeRXy33Y4SZp//9xDgOIU1VmLj1aAo8pOksGOj09ZPGYdh8Nhs6WYeprUIEYD2mDtZzwazi3h/SWTB+Iryek9mwU+8aHLPmEsypNsGcog/m6dFl15XNh3mBtJxfXs7xO6twwy47P72wB/W12Wkjn/zS8zEo887sksnsHNvO7NjDkzR6sV3r+sF7kxq96ZNdl95ilHn46db564KjlxQc/bslE7IhulYyI8i+fquivycs+t+ybKFfeJEvHckXv+TLd/INyHdsoYg3geTbWPKNOP1RAvlhCPlxDvmBFPmRGvmhIPmxJv3BLPnRMvnhOPnxPvkFBf0VC/klEfk1F/lFHflVI/1lKfl1L/mF9TdcuduXBjqylwasWWC1oXrtwTq2WDWP1756olhVHZmiA/iFthbAyJV/+B/Fpxet20oiNQAAAABJRU5ErkJggg==",
    cross = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAMAAADVRocKAAAAkFBMVEWjaQfhzKPz6dTMmQBVVQDChhAA/wB/PwBVqgC/PwC8kj3/VQC1gBqqqlUAAAD++/GueA+jawG3gBO3ewR/fwD//wCveQ7x59CteA2ueA2qVQCveQ2qdQy1iC2qdgz/AACZZweqqgDm1bLLqmjcxZb/fwDCnE/RtHjVu4R/XAu9lUTHo1z/qgCbdRGlbQt/AABKmebdAAAAMHRSTlMU//8FBP8BBAME/wNzAwD/+/z+CgIBz/9wkAOvTv4xAQoD////Av7//wf+/wMVKwI+x4WfAAAD30lEQVR42uWa6XabMBCFyd42rSSQxCIMAmM78Zr3f7uOhsVkqSMnTE96qp+xPR/iztzRkoARj+B/Aygpzb88A81m6c/0l6UCWHWdR1FcAYgGoFkgYJTsGxGgZjMHSJkhAhiWOkDOllQasNwBYkkksmaVEK0ISxLAkpVCFEUIIigSgGRpFDYPYZQxSQKoWR6Fi3kIIlhNAFBMxiJMLlEEQwDAKig4BxFmrCIAXDkJVpw354ngD9BPIMED54tQ5JW2kwOeWBULMec8AREO/n4X+EsAVSASDiIIEKGeHGCcBBuIz7dhdIbfBf51nKEEToQoZ9NrwNZQBXMHcJWw9xYh8C6zXgIUwd/vAn8jEuEPjM9XTgQ5McCwvJOA80cnwm5agNZBLwHn6He+IngCrkcSYKnN2PdJARU4XVhwPhKhmhQgXRU0PQCbzm5KgGVOgkUPuAAR9uBO0wEULrmSHpBg01ETAupnEnRNp54QYJ5J0DUdM6XIaiwBNp14yizSTI4laEXwLLV3AVbd1+aFBJ0Ipr5X9lMAbarKPeadzEW4HQO20JjlnftKVRn9MYCqlftlVc4yt+YdS4AiwDI7m5VOCQ1fPQ+glzXafX3A4JGLP5bAieAIEUIOmK/wE+0FULLCHyh48hhjhGEoNs2z+EBoNviB+0IMM8Ep1JVUJwHWKEzu/SEdgoto8zC/5G+My/nDJhIDJD3ssWSUsW8BrDI7/EDO0jwWURu8WD3OE35iJPPHVdFCIhHn6Qwbnd2ZIb0QYKXE9ydLCB6NgnOvMYJEACkRoqW04xms9/DkwysvtouEnzWSxbYYRIGZ7NfjGazbTOyCN+cGP0KaDtLm8LoDKHCydvMl3nvlHhB4X10w8EOFgB3Lbrq/NRefjA+Ei6YLdoNdL8B25RKne0XFx2eBKdW/IlA7cAvMXmRIoGzITqirc6cCD74RQ75mXSr1IqsrLEBTpqPiLbwhELwYlXVamlHQYDBOg/azLI/2g+n6Ti3M2/QcjKlso5jBYoMX51mOui77mjhdcEOBdblfro8x/mh21nRVHYyq+qTZtdUbdNVrrIddH31pJMoruz6+8lf+49dwlkrduoZzQNt+q+GATR9cw7lVavnBlgkGj1Yis9ctM5NoBdA+9Keavlbmz03fKP31ly1/ZeFFv3QkX/ySL9/JNyDkWyj6TSD5NpZ8I05+lEB/GEJ+nEN+IEV/pEZ+KEh+rEl+MEt+tEx/OE5+vE9+QUF+xUJ/SUR+zUV+UUd+1Uh/WUp+3Ut+YW3VGkQgvHLHSoD9+5JKZGZ1kGXVOVXw9f4zxCqpSAHkMzh//AbyBSylEpyprwAAAABJRU5ErkJggg==",
}
local emoAssets = {} -- name -> asset id usable as an Image

local function ensureEmoAssets()
    if not (writefile and getcustomasset) then return false end
    local all = true
    for name, b64 in pairs(EMO_ART) do
        local file = "c1lown_emo_" .. name .. ".png"
        local ok = pcall(function()
            writefile(file, b64decode(b64))
            emoAssets[name] = getcustomasset(file)
        end)
        if not ok then all = false end
    end
    return all
end

local function isOwner()
    return lp.Name:lower() == OWNER_NAME or lp.DisplayName:lower() == OWNER_NAME
end
-- Friend preset: applied automatically on TheyluvJayden543's account.
-- Icon is left empty; set one in the menu (Text & Icon tab) with an image ID
-- or a file in the executor workspace, then press "Save settings".
local FRIEND_NAME = "theyluvjayden543"
local FRIEND_DISPLAY = "wishyouwerehere"
local FRIEND_PRESET = {
    title = "cut4law", sub = "@TheyluvJayden543",
    font = "GothamBold", subFont = "Gotham",
    titleColor = "FFFFFF", subColor = "C9C2FF", titleStroke = true,
    bg1 = "1A1A24", bg2 = "0A0A0F", bgRot = 60, bgAlpha = 4, bgSpin = false,
    corner = 22, size = 4,
    outline = true, ol1 = "C9C2FF", ol2 = "7C66FF", olThick = 2, olSpin = true, rainbow = false,
    glow = true, glowColor = "7C66FF", glowAlpha = 55, pulse = true,
    iconCorner = 50, iconRing = true, iconRingColor = "C9C2FF",
}
local function isFriendPlayer(plr)
    return plr.Name:lower() == FRIEND_NAME or plr.DisplayName:lower() == FRIEND_NAME
        or plr.DisplayName:lower() == FRIEND_DISPLAY
end
local function isFriend() return isFriendPlayer(lp) end

local function applyBuiltinPreset()
    if isFriend() then
        for k, v in pairs(FRIEND_PRESET) do cfg[k] = v end
        return
    end
    if not isOwner() then return end
    for k, v in pairs(EMO_PRESET) do cfg[k] = v end
    if ensureEmoAssets() and emoAssets.icon then
        cfg.icon = "c1lown_emo_icon.png"
        cfg.decor = true
    else
        cfg.icon = ""
        cfg.decor = false
    end
end

-- built-in presets first, then your own profile file (if any) on top
local function applyOwnerPreset()
    applyBuiltinPreset()
    local prof = readProfile(lp)
    if prof then
        mergeProfile(cfg, prof)
        if type(prof.icon) == "string" and prof.icon ~= "" then
            local path = FOLDER .. "/" .. prof.icon
            if isfile and isfile(path) then cfg.icon = path end
        end
    end
end
applyOwnerPreset()
if not isOwner() then pcall(ensureEmoAssets) end

local function C(hex)
    local ok, c = pcall(Color3.fromHex, tostring(hex))
    return ok and c or Color3.new(1, 1, 1)
end

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local FONTS = { "GothamBold", "GothamBlack", "Gotham", "FredokaOne", "Arcade", "SciFi", "Bangers", "Oswald", "LuckiestGuy", "Michroma", "PermanentMarker", "Creepster", "Fantasy", "SourceSansBold", "Ubuntu" }

-- ====================================================================
-- Tag builder (used for your own tag AND for other script users' tags)
-- ====================================================================
local function createTag(isPeer)
    local t = {}
    t.gui = mk("BillboardGui", { Name = "Tag", ResetOnSpawn = false, Enabled = false, AlwaysOnTop = true, Active = isPeer and true or false }, gui)

    t.glow = mk("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
        Size = UDim2.fromScale(1.3, 1.6), BackgroundTransparency = 1,
        Image = "rbxassetid://6014261993", ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450), ZIndex = 0,
    }, t.gui)

    t.card = mk("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 1,
    }, t.gui)
    t.bgGrad = mk("UIGradient", {}, t.card)
    t.cardCorner = mk("UICorner", {}, t.card)
    t.stroke = mk("UIStroke", { Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, t.card)
    t.strokeGrad = mk("UIGradient", {}, t.stroke)

    t.icon = mk("ImageLabel", {
        BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit,
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.04, 0.5),
        SizeConstraint = Enum.SizeConstraint.RelativeYY, Size = UDim2.fromScale(0.72, 0.72), ZIndex = 2,
    }, t.card)
    t.iconCorner = mk("UICorner", {}, t.icon)
    t.iconRing = mk("UIStroke", { Thickness = 1.5, Transparency = 0.2 }, t.icon)

    t.titleLbl = mk("TextLabel", {
        BackgroundTransparency = 1, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Text = "",
    }, t.card)
    t.subLbl = mk("TextLabel", {
        BackgroundTransparency = 1, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Text = "",
    }, t.card)

    t.decoA = mk("ImageLabel", {
        BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Visible = false,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.975, 0.3),
        SizeConstraint = Enum.SizeConstraint.RelativeYY, Size = UDim2.fromScale(0.34, 0.34), ZIndex = 2,
    }, t.card)
    t.decoB = mk("ImageLabel", {
        BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Visible = false,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.975, 0.72),
        SizeConstraint = Enum.SizeConstraint.RelativeYY, Size = UDim2.fromScale(0.26, 0.26), ZIndex = 2,
    }, t.card)

    if isPeer then
        -- invisible button covering the whole tag: click = teleport
        t.hit = mk("TextButton", {
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1), ZIndex = 10,
        }, t.card)
    end
    return t
end

local function layoutTag(t, d)
    local k = d.size / 4
    local h = 1.6 * k
    local hasImg = t.icon.Image ~= ""
    local hasSub = d.sub ~= ""
    local hasText = d.title ~= ""
    local chars = math.max(#d.title, #d.sub, 6)
    local w = (h * (hasImg and 0.95 or 0.35) + h * 0.3 * math.min(chars, 22) * 0.55) * (d.widthPct / 100)
    local decor = d.decor and emoAssets.spark ~= nil and emoAssets.cross ~= nil
    if decor then w = w + 0.5 * h end
    t.baseW, t.baseH, t.gap = w, h, 1.4 + d.offset / 10
    t.zoomF = nil -- force the zoom factor to be re-applied
    t.gui.Size = UDim2.fromScale(w, h)
    t.gui.StudsOffset = Vector3.new(0, t.gap + h / 2, 0)
    t.icon.Visible = hasImg
    local tx = hasImg and (0.04 * w + 0.72 * h + 0.08 * h) / w or 0.06
    local reserve = decor and (0.4 * h / w + 0.03) or 0
    local tw = math.max(1 - tx - 0.04 - reserve, 0.1)
    t.decoA.Visible = decor
    t.decoB.Visible = decor
    t.titleLbl.Visible = hasText
    t.subLbl.Visible = hasSub
    t.titleLbl.Position = UDim2.fromScale(tx, hasSub and 0.08 or 0.15)
    t.titleLbl.Size = UDim2.fromScale(tw, hasSub and 0.5 or 0.7)
    t.subLbl.Position = UDim2.fromScale(tx, hasText and 0.58 or 0.2)
    t.subLbl.Size = UDim2.fromScale(tw, hasText and 0.32 or 0.6)
end

local function applyFont(lbl, name)
    local ok, f = pcall(function() return Enum.Font[name] end)
    if ok and f then lbl.Font = f end
end

local function styleTag(t, d)
    t.bgGrad.Color = ColorSequence.new(C(d.bg1), C(d.bg2))
    t.card.BackgroundTransparency = math.clamp(d.bgAlpha / 100, 0, 1)
    t.cardCorner.CornerRadius = UDim.new(math.clamp(d.corner / 100, 0, 0.5), 0)

    t.stroke.Enabled = d.outline
    t.stroke.Thickness = d.olThick
    t.strokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C(d.ol1)),
        ColorSequenceKeypoint.new(0.5, C(d.ol2)),
        ColorSequenceKeypoint.new(1, C(d.ol1)),
    })

    t.glow.Visible = d.glow
    t.glow.ImageColor3 = C(d.glowColor)
    t.glow.ImageTransparency = math.clamp(d.glowAlpha / 100, 0, 1)

    t.titleLbl.Text, t.subLbl.Text = d.title, d.sub
    t.titleLbl.TextColor3, t.subLbl.TextColor3 = C(d.titleColor), C(d.subColor)
    t.titleLbl.TextStrokeTransparency = d.titleStroke and 0.6 or 1
    applyFont(t.titleLbl, d.font)
    applyFont(t.subLbl, d.subFont)

    t.iconCorner.CornerRadius = UDim.new(math.clamp(d.iconCorner / 100, 0, 0.5), 0)
    t.iconRing.Enabled = d.iconRing
    t.iconRing.Color = C(d.iconRingColor)

    t.decoA.Image = emoAssets.spark or ""
    t.decoB.Image = emoAssets.cross or ""

    -- viewer-side preferences
    t.gui.AlwaysOnTop = cfg.onTop
    t.gui.MaxDistance = (cfg.maxDist >= 1000) and math.huge or cfg.maxDist
    layoutTag(t, d)
end

local localTag = createTag(false)
local peerTags = {} -- [userId] = tag (with .data)
local peerHum = {} -- [userId] = Humanoid whose default name we hid (profile players)
local onChanged
local mimic = nil -- size/offset/anchor read from the tag we replaced

local function apply()
    styleTag(localTag, cfg)
    for _, pt in pairs(peerTags) do styleTag(pt, pt.data) end
    if onChanged then onChanged() end
end

local function setIcon(src)
    src = ((src or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if src == "" then
        localTag.icon.Image = ""
        layoutTag(localTag, cfg)
        return true
    end
    local id = src:match("^(%d+)$") or src:match("^rbxassetid://(%d+)$") or src:match("[?&]id=(%d+)")
    if id then
        localTag.icon.Image = "rbxassetid://" .. id
    elseif src:match("^https?://") then
        if not (writefile and getcustomasset) then return false, "Executor can't load linked images" end
        local okd, data = pcall(game.HttpGet, game, src)
        if not okd or type(data) ~= "string" or #data == 0 then return false, "Couldn't download that link" end
        local ext = (src:match("%.(%a+)[^%.]*$") or "png"):lower()
        if ext ~= "png" and ext ~= "jpg" and ext ~= "jpeg" then ext = "png" end
        local file = "c1lown_nametag_icon_" .. os.time() .. "." .. ext
        if not pcall(writefile, file, data) then return false, "Couldn't save the image" end
        local oka, asset = pcall(getcustomasset, file)
        if not oka then return false, "Couldn't load the image file" end
        localTag.icon.Image = asset
    else
        if not (isfile and getcustomasset) then return false, "Executor can't load local files" end
        if not isfile(src) then return false, "File not found in workspace: " .. src end
        local oka, asset = pcall(getcustomasset, src)
        if not oka then return false, "Couldn't load that file" end
        localTag.icon.Image = asset
    end
    layoutTag(localTag, cfg)
    return true
end

-- animation loop (your tag + everyone else's)
local function animate(t, d, elapsed)
    t.strokeGrad.Rotation = d.olSpin and ((elapsed * 70) % 360) or 0
    t.bgGrad.Rotation = d.bgSpin and ((d.bgRot + elapsed * 40) % 360) or d.bgRot
    if d.rainbow then
        local h = (elapsed * 0.2) % 1
        t.strokeGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHSV(h, 0.8, 1)),
            ColorSequenceKeypoint.new(0.5, Color3.fromHSV((h + 0.15) % 1, 0.8, 1)),
            ColorSequenceKeypoint.new(1, Color3.fromHSV(h, 0.8, 1)),
        })
    end
    if d.glow and d.pulse then
        t.glow.ImageTransparency = math.clamp(d.glowAlpha / 100 + math.sin(elapsed * 2) * 0.12, 0, 1)
    end
end

-- zoom scaling: the tag grows when the camera is far and shrinks when it is
-- close, by the "Zoom scaling" amount (0 = normal, 100 = constant screen size)
local function applyZoom(t)
    if t == localTag and cfg.hideForeign and cfg.matchForeign and mimic then
        -- take over the replaced tag's exact size and position
        local s = cfg.matchScale / 100
        t.gui.Size = UDim2.new(mimic.size.X.Scale * s, mimic.size.X.Offset * s, mimic.size.Y.Scale * s, mimic.size.Y.Offset * s)
        t.gui.StudsOffset = mimic.offset + Vector3.new(0, cfg.matchHeight / 10, 0)
        t.gui.StudsOffsetWorldSpace = mimic.worldOffset
        t.gui.ExtentsOffset = mimic.extents
        t.gui.SizeOffset = mimic.sizeOffset
        t.gui.MaxDistance = mimic.maxDist
        t.zoomF = nil
        return
    end
    local head = t.gui.Adornee
    local camera = workspace.CurrentCamera
    if not (t.baseW and head and camera) then return end
    local k = math.clamp((cfg.zoomScale or 0) / 100, 0, 1)
    local f = 1
    if k > 0 then
        local dist = (camera.CFrame.Position - head.Position).Magnitude
        f = math.clamp((dist / 12) ^ k, 0.4, 8)
    end
    if t.zoomF and math.abs(f - t.zoomF) < 0.003 then return end
    t.zoomF = f
    t.gui.Size = UDim2.fromScale(t.baseW * f, t.baseH * f)
    t.gui.StudsOffset = Vector3.new(0, t.gap + t.baseH * f / 2, 0)
end

task.spawn(function()
    local elapsed = 0
    while gui.Parent do
        elapsed += task.wait()
        animate(localTag, cfg, elapsed)
        applyZoom(localTag)
        for _, pt in pairs(peerTags) do
            if pt.gui.Enabled then
                animate(pt, pt.data, elapsed)
                applyZoom(pt)
            end
        end
    end
end)

-- ====================================================================
-- Hide other overhead tags on your character (e.g. "AK USER").
-- Tags are disabled the moment they appear, and turned off again if the
-- other script re-enables them, so execution order doesn't matter.
-- ====================================================================
local hiddenForeign = {}   -- [BillboardGui] = true
local watched = {}

local function isForeign(d)
    return d:IsA("BillboardGui") and not d:IsDescendantOf(gui)
end

-- The other tag is hidden by shrinking it to nothing (NOT by disabling it), so
-- its Enabled property keeps showing what the other script wants. That is how
-- your tag follows the other script's nametag button.
local ZERO = UDim2.new(0, 0, 0, 0)
local origProps = {} -- [BillboardGui] = { size = UDim2, clips = bool }

local function suppress(d)
    if not isForeign(d) then return end
    if not (cfg.enabled and cfg.hideForeign) then return end
    hiddenForeign[d] = true
    if not origProps[d] then
        -- the real size is kept on the tag itself, so a re-executed script
        -- never mistakes the shrunk size for the original
        local sz = d:GetAttribute("c1lownSize")
        local clips = d:GetAttribute("c1lownClips")
        if sz == nil then
            sz = d.Size
            if sz == ZERO then sz = UDim2.fromOffset(160, 50) end -- stuck from an old run: best guess
            clips = d.ClipsDescendants
            pcall(function()
                d:SetAttribute("c1lownSize", sz)
                d:SetAttribute("c1lownClips", clips)
            end)
        end
        origProps[d] = { size = sz, clips = clips and true or false }
    end
    local function hide()
        if not (cfg.enabled and cfg.hideForeign) then return end
        if d.Size ~= ZERO then
            origProps[d].size = d.Size -- other script resized it: remember, hide again
            pcall(function() d:SetAttribute("c1lownSize", d.Size) end)
            d.Size = ZERO
        end
        d.ClipsDescendants = true
    end
    hide()
    if not watched[d] then
        watched[d] = connect(d:GetPropertyChangedSignal("Size"), hide)
    end
end

local function restoreForeign()
    for d in pairs(hiddenForeign) do
        local o = origProps[d]
        if d.Parent and o then
            d.Size = o.size
            d.ClipsDescendants = o.clips
            pcall(function()
                d:SetAttribute("c1lownSize", nil)
                d:SetAttribute("c1lownClips", nil)
            end)
        end
        origProps[d] = nil
        hiddenForeign[d] = nil
    end
end

-- what the other script currently wants: is its text tag on?
-- Yours only hides after the other tag has been seen ON and then goes off,
-- so a tag that never reports "on" can never make yours vanish.
local seenOn = false
local function foreignState()
    local on = false
    for d in pairs(hiddenForeign) do
        if d.Parent and d:FindFirstChildWhichIsA("TextLabel", true) then
            if d.Enabled and (d.Adornee ~= nil or d.Parent:IsA("BasePart")) then
                on = true
                seenOn = true
            end
        end
    end
    return seenOn, on
end

local function watchCharacter(c)
    for _, d in ipairs(c:GetDescendants()) do suppress(d) end
    connect(c.DescendantAdded, function(d) task.defer(suppress, d) end)
end

-- tags parented to PlayerGui but adorned to your character
local function checkGuiTag(d)
    if not d:IsA("BillboardGui") then return end
    local function test()
        local a = d.Adornee
        if a and lp.Character and a:IsDescendantOf(lp.Character) then suppress(d) end
    end
    test()
    connect(d:GetPropertyChangedSignal("Adornee"), test)
end
local pg = lp:WaitForChild("PlayerGui")
for _, d in ipairs(pg:GetDescendants()) do checkGuiTag(d) end
connect(pg.DescendantAdded, function(d) task.defer(checkGuiTag, d) end)

if lp.Character then watchCharacter(lp.Character) end
connect(lp.CharacterAdded, watchCharacter)

-- re-hide existing tags after the toggle is switched back on
local function rescanForeign()
    local c = lp.Character
    if c then
        for _, d in ipairs(c:GetDescendants()) do suppress(d) end
    end
    for _, d in ipairs(pg:GetDescendants()) do
        local a = d:IsA("BillboardGui") and d.Adornee
        if a and c and a:IsDescendantOf(c) then suppress(d) end
    end
end
local lastWantHide = true

local hiddenHum
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        local wantHide = cfg.enabled and cfg.hideForeign
        if not wantHide then restoreForeign() end
        if wantHide and not lastWantHide then rescanForeign() end
        lastWantHide = wantHide
        local c = lp.Character
        local head = c and c:FindFirstChild("Head")
        local h = c and c:FindFirstChildOfClass("Humanoid")

        -- read the replaced tag's size / position so ours can copy it exactly
        mimic = nil
        if cfg.enabled and cfg.hideForeign and cfg.matchForeign then
            for d in pairs(hiddenForeign) do
                if d.Parent and d:FindFirstChildWhichIsA("TextLabel", true) then
                    local a = d.Adornee or d.Parent
                    local ad = (a and a:IsA("BasePart") and c and a:IsDescendantOf(c)) and a or nil
                    mimic = {
                        size = origProps[d] and origProps[d].size or d.Size, offset = d.StudsOffset, worldOffset = d.StudsOffsetWorldSpace,
                        extents = d.ExtentsOffset, sizeOffset = d.SizeOffset, maxDist = d.MaxDistance,
                        adornee = ad,
                    }
                    break
                end
            end
        end

        local show = cfg.enabled and head ~= nil and (cfg.title ~= "" or cfg.sub ~= "" or localTag.icon.Image ~= "")
        if show and wantHide and cfg.followForeign then
            -- follow the other script's nametag button: its tag on = ours on
            local seen, otherOn = foreignState()
            if seen and not otherOn then show = false end
        end
        localTag.gui.Adornee = show and ((mimic and mimic.adornee) or head) or nil
        localTag.gui.Enabled = show
        if cfg.enabled and cfg.hideDefault and h then
            h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hiddenHum = h
        elseif hiddenHum then
            pcall(function() hiddenHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end)
            hiddenHum = nil
        end

        -- other script users' tags
        for uid, pt in pairs(peerTags) do
            local plr = Players:GetPlayerByUserId(uid)
            local ph = plr and plr.Character and plr.Character:FindFirstChild("Head")
            local d = pt.data
            local pshow = cfg.showOthers and d.enabled and ph ~= nil
                and (d.title ~= "" or d.sub ~= "" or pt.icon.Image ~= "")
            pt.gui.Adornee = pshow and ph or nil
            pt.gui.Enabled = pshow and true or false

            -- profile players: swap their default name for the profile tag
            local phum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
            if pt.hasProfile and phum then
                if pshow then
                    phum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                    peerHum[uid] = phum
                elseif peerHum[uid] then
                    pcall(function() peerHum[uid].DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end)
                    peerHum[uid] = nil
                end
            end
        end
    end
end)

-- ====================================================================
-- UI
-- ====================================================================
local BG = Color3.fromRGB(15, 15, 21)
local PANEL = Color3.fromRGB(21, 21, 29)
local ELEM = Color3.fromRGB(30, 30, 41)
local STROKE_C = Color3.fromRGB(46, 46, 62)
local TRACK = Color3.fromRGB(52, 52, 70)
local ACCENT = Color3.fromRGB(124, 102, 255)
local ACCENT2 = Color3.fromRGB(72, 150, 255)
local TEXT = Color3.fromRGB(240, 240, 246)
local SUB = Color3.fromRGB(150, 150, 172)
local WHITE = Color3.new(1, 1, 1)

local function corner(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function ustroke(o, color) return mk("UIStroke", { Color = color or STROKE_C, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o) end
local function label(parent, text, size, font, color, xalign)
    return mk("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size or 13, Font = font or Enum.Font.Gotham,
        TextColor3 = color or TEXT, TextXAlignment = xalign or Enum.TextXAlignment.Left,
    }, parent)
end

local root = mk("Frame", {
    Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(540, 420),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = BG, BorderSizePixel = 0, Visible = true,
}, gui)
corner(root, 12)
ustroke(root)

local titleBar = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
corner(titleBar, 12)
mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, titleBar)
local tTxt = label(titleBar, "c1lown nametag", 15, Enum.Font.GothamBold, TEXT)
tTxt.Position, tTxt.Size = UDim2.fromOffset(16, 0), UDim2.new(0, 150, 1, 0)
local tHint = label(titleBar, cfg.menuKey .. " to toggle", 11, Enum.Font.Gotham, SUB)
tHint.Position, tHint.Size = UDim2.fromOffset(150, 2), UDim2.new(0, 150, 1, 0)
local closeBtn = mk("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(26, 26),
    BackgroundColor3 = ELEM, AutoButtonColor = false, Text = "X", TextColor3 = SUB, Font = Enum.Font.GothamBold, TextSize = 12,
}, titleBar)
corner(closeBtn, 7)
closeBtn.MouseButton1Click:Connect(function() root.Visible = false end)

do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, root.Position
        end
    end)
    connect(UserInputService.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local sidebar = mk("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(0, 124, 1, -64), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
local statusBar = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
corner(statusBar, 12)
mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, statusBar)
local statusLbl = label(statusBar, "Ready", 11, Enum.Font.Gotham, SUB)
statusLbl.Position, statusLbl.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0)
statusLbl.ZIndex = 2
local function status(msg) statusLbl.Text = tostring(msg) end

local pages, tabButtons = {}, {}
local function selectTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        b.TextColor3 = (n == name) and WHITE or SUB
        b.BackgroundColor3 = (n == name) and ACCENT or PANEL
    end
end
local tabCount = 0
local function newTab(name)
    tabCount += 1
    local b = mk("TextButton", {
        Position = UDim2.new(0, 8, 0, 10 + (tabCount - 1) * 38), Size = UDim2.new(1, -16, 0, 32),
        BackgroundColor3 = PANEL, Text = name, TextColor3 = SUB, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
    }, sidebar)
    corner(b, 8)
    b.MouseButton1Click:Connect(function() selectTab(name) end)
    tabButtons[name] = b
    local scroll = mk("ScrollingFrame", {
        Position = UDim2.fromOffset(136, 50), Size = UDim2.new(1, -148, 1, -80), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = ACCENT, AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(), Visible = false,
    }, root)
    mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    mk("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, scroll)
    pages[name] = scroll
    return scroll
end

local syncers = {}
local function syncAll() for _, f in ipairs(syncers) do f() end end

local function addLabel(page, text)
    local l = label(page, string.upper(text), 11, Enum.Font.GothamBold, SUB)
    l.Size = UDim2.new(1, 0, 0, 18)
    return l
end

local function addButton(page, text, callback)
    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = ELEM, Text = text, TextColor3 = TEXT,
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true,
    }, page)
    corner(b, 8)
    ustroke(b)
    b.MouseButton1Click:Connect(callback)
    return b
end

local function addToggle(page, text, key)
    local row = mk("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = ELEM, Text = "", AutoButtonColor = false }, page)
    corner(row, 8)
    ustroke(row)
    local l = label(row, text, 13, Enum.Font.Gotham, TEXT)
    l.Position, l.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -70, 1, 0)
    local track = mk("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(38, 20), BorderSizePixel = 0 }, row)
    corner(track, 10)
    local knob = mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
    corner(knob, 7)
    local function sync()
        local on = cfg[key]
        track.BackgroundColor3 = on and ACCENT or TRACK
        knob.Position = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
    end
    row.MouseButton1Click:Connect(function() cfg[key] = not cfg[key] sync() apply() end)
    table.insert(syncers, sync)
    sync()
end

local function addSlider(page, text, key, min, max)
    local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = ELEM }, page)
    corner(f, 8)
    ustroke(f)
    local lbl = label(f, text, 12, Enum.Font.Gotham, TEXT)
    lbl.Position, lbl.Size = UDim2.fromOffset(12, 6), UDim2.new(0.6, 0, 0, 18)
    local val = label(f, "", 12, Enum.Font.GothamBold, ACCENT, Enum.TextXAlignment.Right)
    val.AnchorPoint, val.Position, val.Size = Vector2.new(1, 0), UDim2.new(1, -12, 0, 6), UDim2.new(0.4, 0, 0, 18)
    local hit = mk("Frame", { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 20), BackgroundTransparency = 1 }, f)
    local bar = mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = TRACK, BorderSizePixel = 0 }, hit)
    corner(bar, 3)
    local fill = mk("Frame", { BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, bar)
    corner(fill, 3)
    local knob = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, bar)
    corner(knob, 7)

    local function show()
        local r = (cfg[key] - min) / (max - min)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
        val.Text = tostring(cfg[key])
    end
    local sliding = false
    local function update(x)
        local r = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor(min + (max - min) * r + 0.5)
        if v ~= cfg[key] then cfg[key] = v apply() end
        show()
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            update(i.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(i)
        if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then update(i.Position.X) end
    end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then sliding = false end
    end)
    table.insert(syncers, show)
    show()
end

local function newBox(page, placeholder, height)
    local tb = mk("TextBox", {
        Size = UDim2.new(1, 0, 0, height or 34), BackgroundColor3 = ELEM, TextColor3 = TEXT,
        PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(125, 125, 145), Text = "",
        ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, page)
    corner(tb, 8)
    ustroke(tb)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tb)
    return tb
end

local function addText(page, placeholder, key)
    local tb = newBox(page, placeholder, 34)
    local function sync() tb.Text = cfg[key] end
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        if tb.Text ~= cfg[key] then cfg[key] = tb.Text apply() end
    end)
    table.insert(syncers, sync)
    sync()
end

local function addColor(page, text, key)
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = ELEM }, page)
    corner(row, 8)
    ustroke(row)
    local l = label(row, text, 13, Enum.Font.Gotham, TEXT)
    l.Position, l.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -140, 1, 0)
    local sw = mk("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0 }, row)
    corner(sw, 6)
    ustroke(sw, Color3.fromRGB(90, 90, 110))
    local tb = mk("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(80, 24),
        BackgroundColor3 = BG, TextColor3 = TEXT, Font = Enum.Font.Code, TextSize = 12, ClearTextOnFocus = false, Text = "",
    }, row)
    corner(tb, 6)
    local function sync()
        tb.Text = "#" .. cfg[key]
        sw.BackgroundColor3 = C(cfg[key])
    end
    tb.FocusLost:Connect(function()
        local hex = tb.Text:gsub("[^%x]", "")
        if #hex == 6 then
            cfg[key] = hex:upper()
            apply()
        else
            status("Enter a 6-digit hex colour, e.g. 7C66FF")
        end
        sync()
    end)
    table.insert(syncers, sync)
    sync()
end

local function addFontCycle(page, text, key)
    local b
    local function sync() b.Text = text .. ": " .. cfg[key] end
    b = addButton(page, "", function()
        local idx = table.find(FONTS, cfg[key]) or 0
        cfg[key] = FONTS[idx % #FONTS + 1]
        apply()
        sync()
    end)
    table.insert(syncers, sync)
    sync()
end

local textTab = newTab("Text & Icon")
addLabel(textTab, "Tag")
addToggle(textTab, "Show nametag", "enabled")
addToggle(textTab, "Hide default name", "hideDefault")
addToggle(textTab, "Hide other overhead tags (AK USER)", "hideForeign")
addToggle(textTab, "Match replaced tag's size/position", "matchForeign")
addToggle(textTab, "Follow other script's nametag button", "followForeign")
addButton(textTab, "Debug: print replaced tag info", function()
    local n = 0
    for d in pairs(hiddenForeign) do
        n += 1
        local o = origProps[d]
        print(("[nametag debug] %s | Enabled=%s | Adornee=%s | origSize=%s | hasText=%s"):format(
            d:GetFullName(), tostring(d.Enabled), tostring(d.Adornee), tostring(o and o.size),
            tostring(d:FindFirstChildWhichIsA("TextLabel", true) ~= nil)))
    end
    print(("[nametag debug] ours: Enabled=%s Adornee=%s Size=%s | matching=%s"):format(
        tostring(localTag.gui.Enabled), tostring(localTag.gui.Adornee), tostring(localTag.gui.Size), tostring(mimic ~= nil)))
    status(("Replaced %d tag(s); ours %s (details in console)"):format(n, localTag.gui.Enabled and "visible" or "hidden"))
end)
addLabel(textTab, "Text")
addText(textTab, "Title", "title")
addText(textTab, "Subtitle (small text, can be empty)", "sub")
addFontCycle(textTab, "Title font", "font")
addFontCycle(textTab, "Subtitle font", "subFont")
addColor(textTab, "Title colour", "titleColor")
addColor(textTab, "Subtitle colour", "subColor")
addToggle(textTab, "Title outline", "titleStroke")
addLabel(textTab, "Icon")
local iconBox = newBox(textTab, "Image ID, link, or workspace file", 34)
iconBox.Text = cfg.icon
local function applyIcon(src)
    cfg.icon = src
    task.spawn(function()
        local ok, err = setIcon(src)
        status(ok and (src:match("%S") and "Icon set" or "Icon cleared") or tostring(err))
        if onChanged then onChanged() end
    end)
end
addButton(textTab, "Apply Icon", function() applyIcon(iconBox.Text) end)
addButton(textTab, "Clear Icon", function() iconBox.Text = "" applyIcon("") end)
addSlider(textTab, "Icon roundness (50 = circle)", "iconCorner", 0, 50)
addToggle(textTab, "Icon ring", "iconRing")
addColor(textTab, "Icon ring colour", "iconRingColor")

local styleTab = newTab("Style")
addLabel(styleTab, "Background gradient")
addColor(styleTab, "Colour 1", "bg1")
addColor(styleTab, "Colour 2", "bg2")
addSlider(styleTab, "Gradient angle", "bgRot", 0, 360)
addToggle(styleTab, "Spin gradient", "bgSpin")
addSlider(styleTab, "Transparency %", "bgAlpha", 0, 100)
addSlider(styleTab, "Corner roundness", "corner", 0, 50)
addLabel(styleTab, "Outline")
addToggle(styleTab, "Outline", "outline")
addColor(styleTab, "Colour 1", "ol1")
addColor(styleTab, "Colour 2", "ol2")
addSlider(styleTab, "Thickness", "olThick", 1, 8)
addToggle(styleTab, "Spin outline", "olSpin")
addToggle(styleTab, "Rainbow outline", "rainbow")
addLabel(styleTab, "Glow")
addToggle(styleTab, "Glow", "glow")
addColor(styleTab, "Glow colour", "glowColor")
addSlider(styleTab, "Glow transparency %", "glowAlpha", 0, 100)
addToggle(styleTab, "Pulse glow", "pulse")
addLabel(styleTab, "Images")
addToggle(styleTab, "Decorative images (gold sparkles)", "decor")

local layoutTab = newTab("Layout")
addLabel(layoutTab, "Size and position")
addSlider(layoutTab, "Tag size", "size", 1, 12)
addSlider(layoutTab, "Width %", "widthPct", 50, 200)
addSlider(layoutTab, "Height above head", "offset", 0, 60)
addSlider(layoutTab, "Max distance (1000 = unlimited)", "maxDist", 20, 1000)
addSlider(layoutTab, "Zoom scaling (0 = normal, 100 = constant)", "zoomScale", 0, 100)
addLabel(layoutTab, "When matching the replaced tag")
addSlider(layoutTab, "Resize % (100 = same as replaced tag)", "matchScale", 50, 200)
addSlider(layoutTab, "Nudge height (tenths of a stud)", "matchHeight", -30, 60)
addToggle(layoutTab, "Show through walls", "onTop")
addLabel(layoutTab, "Menu key")
local listeningKey = false
local keyBtn
local function syncKey()
    keyBtn.Text = listeningKey and "Press a key... (Esc to cancel)" or ("Menu key: " .. cfg.menuKey .. "  (click to change)")
    tHint.Text = cfg.menuKey .. " to toggle"
end
keyBtn = addButton(layoutTab, "", function()
    listeningKey = true
    syncKey()
end)
table.insert(syncers, syncKey)
syncKey()
addLabel(layoutTab, "Config file")
local editName, editPlr, editBackup, saveToken = nil, nil, nil, 0 -- edit mode state (see Players tab)
addButton(layoutTab, "Save settings", function()
    if editName then status("Stop editing the other profile first") return end
    status(saveConfig() and "Saved, loads automatically next time" or "Couldn't save (executor has no writefile)")
end)
addButton(layoutTab, "Load saved settings", function()
    if loadSaved() then
        syncAll() iconBox.Text = cfg.icon apply() applyIcon(cfg.icon)
        status("Loaded")
    else
        status("No saved settings found")
    end
end)
addButton(layoutTab, "Reset to defaults", function()
    for k, v in pairs(DEFAULT) do cfg[k] = v end
    applyOwnerPreset()
    syncAll() iconBox.Text = cfg.icon apply() setIcon(cfg.icon)
    status("Reset")
end)

-- ====================================================================
-- Players tab
-- ====================================================================
local playersTab = newTab("Players")
addLabel(playersTab, "Script users")
addToggle(playersTab, "Show other script users' tags", "showOthers")
addToggle(playersTab, "Let other script users detect me", "beacon")
addToggle(playersTab, "Alert me when someone executes it", "notify")
addToggle(playersTab, "Auto-create profile files for players", "autoProfiles")

local scriptUsers = {}
local listHolder = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 50 }, playersTab)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)

local function tpTo(plr)
    local c = plr.Character
    local r = c and c:FindFirstChild("HumanoidRootPart")
    local mine = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not (r and mine) then status("Can't teleport: no character") return end
    local pos = r.Position + r.CFrame.LookVector * 4 + Vector3.new(0, 1.5, 0)
    mine.CFrame = CFrame.lookAt(pos, r.Position)
    status("Teleported to " .. plr.DisplayName)
end

local refreshPlayers
function refreshPlayers()
    for _, ch in ipairs(listHolder:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then table.insert(list, plr) end
    end
    table.sort(list, function(a, b)
        local ua, ub = scriptUsers[a.UserId] and 0 or 1, scriptUsers[b.UserId] and 0 or 1
        if ua ~= ub then return ua < ub end
        return a.DisplayName:lower() < b.DisplayName:lower()
    end)
    for idx, plr in ipairs(list) do
        local isUser = scriptUsers[plr.UserId]
        local b = addButton(listHolder, (isUser and "★ " or "") .. plr.DisplayName .. "  (@" .. plr.Name .. ")", function() tpTo(plr) end)
        b.LayoutOrder = idx
        if isUser then b.TextColor3 = Color3.fromRGB(255, 214, 102) end
    end
end

local nextIdx = 0
addButton(playersTab, "Teleport to next script user", function()
    local users = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and scriptUsers[plr.UserId] then table.insert(users, plr) end
    end
    if #users == 0 then status("No other script users found yet") return end
    nextIdx = nextIdx % #users + 1
    tpTo(users[nextIdx])
end)
addButton(playersTab, "Refresh list", function() refreshPlayers() end)
addLabel(playersTab, "Players (★ = running this script, click to teleport)")

-- ====================================================================
-- Other script users' tags (click the tag = teleport to that player)
-- ====================================================================
local function defaultsFor(plr)
    local d = {}
    for k, v in pairs(DEFAULT) do d[k] = v end
    d.title, d.sub, d.icon = plr.DisplayName, "@" .. plr.Name, ""
    -- built-in preset for the friend, so it shows on your screen too
    local preset = isFriendPlayer(plr)
    if preset then
        for k, v in pairs(FRIEND_PRESET) do d[k] = v end
    end
    local prof = readProfile(plr)
    if prof then mergeProfile(d, prof) end
    return d, prof or (preset and {} or nil)
end

local function getPeerTag(plr)
    local uid = plr.UserId
    local t = peerTags[uid]
    if t then return t end
    t = createTag(true)
    local prof
    t.data, prof = defaultsFor(plr)
    t.hasProfile = prof ~= nil
    t.icon.Image = ""
    if prof and type(prof.icon) == "string" then
        local a = resolveAsset(prof.icon)
        if a then
            t.icon.Image = a
        elseif prof.icon ~= "" then
            warnOnce("icon" .. uid, ("[nametag] couldn't load icon '%s' for %s. Looked for workspace/%s/%s (file names are exact, e.g. cut4law.png)"):format(
                prof.icon, plr.Name, FOLDER, prof.icon))
        end
    end
    peerTags[uid] = t
    t.hit.MouseButton1Click:Connect(function()
        local p = Players:GetPlayerByUserId(uid)
        if p then tpTo(p) else status("That player left") end
    end)
    t.hit.MouseEnter:Connect(function() t.stroke.Thickness = t.data.olThick + 2 end)
    t.hit.MouseLeave:Connect(function() t.stroke.Thickness = t.data.olThick end)
    styleTag(t, t.data)
    return t
end

local function removePeer(uid)
    local hm = peerHum[uid]
    if hm then
        pcall(function() hm.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end)
        peerHum[uid] = nil
    end
    local t = peerTags[uid]
    if t then
        pcall(function() t.gui:Destroy() end)
        peerTags[uid] = nil
    end
end

-- give a tag to every player in the server that has a profile (local or online)
local function scanProfiles()
    for _, plr in ipairs(Players:GetPlayers()) do
        ensureProfileFile(plr)
        if plr ~= lp and not peerTags[plr.UserId] and (readProfile(plr) or isFriendPlayer(plr)) then
            getPeerTag(plr)
        end
    end
end

-- ====================================================================
-- Silent detection (NO chat messages)
-- Script users play two tiny-weight Roblox emote animations at once.
-- Animations replicate to everyone, so other copies of this script can
-- spot that pair on your character and show your tag. Nothing is typed.
-- Other people's tags use the default style (nothing else can be sent).
-- ====================================================================
local MARK_IDS = { 507770239, 507770453 } -- R15 wave + point = "script user"
-- four more emotes act as 4 bits = a number 1-15 that names your executor
local BIT_IDS = { 507770677, 507770818, 507771019, 507776043 } -- cheer, laugh, dance, dance2
local EXEC_LIST = {
    "Potassium", "Madium", "Wave", "Volcano", "Solara", "Xeno", "Velocity", "Delta",
    "Fluxus", "Codex", "Arceus X", "Hydrogen", "KRNL", "Seliware", "Synapse",
}

local execName = "Unknown"
pcall(function()
    if identifyexecutor then execName = tostring((identifyexecutor())) end
end)
local function squash(t) return (t:lower():gsub("[%s%-_]", "")) end
local execCode = 0
do
    local n = squash(execName)
    for i, name in ipairs(EXEC_LIST) do
        if n:find(squash(name), 1, true) then execCode = i break end
    end
end
local execKey = EXEC_LIST[execCode]

local function codeIds(code)
    local ids = {}
    for bit, id in ipairs(BIT_IDS) do
        if math.floor(code / 2 ^ (bit - 1)) % 2 == 1 then ids[#ids + 1] = id end
    end
    return ids
end

local toast
local function showToast(plr, ex)
    if toast then toast:Destroy() end
    local f = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -70), Size = UDim2.fromOffset(330, 52),
        BackgroundColor3 = Color3.fromRGB(24, 24, 34), BorderSizePixel = 0, ZIndex = 20,
    }, gui)
    corner(f, 10)
    ustroke(f, ACCENT)
    toast = f
    local l = label(f, "★ " .. plr.DisplayName .. " is running the script" .. (ex and (" (" .. ex .. ")") or ""), 13, Enum.Font.GothamMedium, TEXT)
    l.Position, l.Size, l.ZIndex = UDim2.fromOffset(14, 0), UDim2.new(1, -90, 1, 0), 21
    l.TextTruncate = Enum.TextTruncate.AtEnd
    local b = mk("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(60, 30),
        BackgroundColor3 = ACCENT, Text = "TP", TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 21,
    }, f)
    corner(b, 8)
    b.MouseButton1Click:Connect(function() tpTo(plr) f:Destroy() end)
    f:TweenPosition(UDim2.new(0.5, 0, 0, 16), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.35, true)
    task.delay(8, function()
        if toast == f then
            f:TweenPosition(UDim2.new(0.5, 0, 0, -70), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3, true)
            task.delay(0.35, function() if toast == f then toast = nil end f:Destroy() end)
        end
    end)
end

local function setExec(plr, ex)
    local t = peerTags[plr.UserId]
    if not t or t.hasProfile then return end
    local sub = "@" .. plr.Name .. (ex and (" | " .. ex) or "")
    if t.data.sub ~= sub then
        t.data.sub = sub
        styleTag(t, t.data)
    end
end

local function markUser(plr, ex)
    local uid = plr.UserId
    if scriptUsers[uid] then setExec(plr, ex) return end
    scriptUsers[uid] = true
    local t = getPeerTag(plr)
    if not t.hasProfile then
        t.icon.Image = "rbxthumb://type=AvatarHeadShot&id=" .. uid .. "&w=150&h=150"
        t.data.iconCorner = 50
    end
    styleTag(t, t.data)
    setExec(plr, ex)
    refreshPlayers()
    status(plr.DisplayName .. " is running the script" .. (ex and (" (" .. ex .. ")") or ""))
    if cfg.notify then showToast(plr, ex) end
end

local function unmarkUser(uid)
    if not scriptUsers[uid] then return end
    scriptUsers[uid] = nil
    removePeer(uid)
    refreshPlayers()
end

-- my marker -------------------------------------------------------------
local markTracks, markAnimator = {}, nil

local function stopBeacon()
    for _, tr in ipairs(markTracks) do pcall(function() tr:Stop(0) end) end
    markTracks, markAnimator = {}, nil
end

local function startBeacon()
    stopBeacon()
    local c = lp.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local ids = {}
    for _, id in ipairs(MARK_IDS) do ids[#ids + 1] = id end
    for _, id in ipairs(codeIds(execCode)) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id
        local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
        if ok and tr then
            tr.Looped = true
            tr.Priority = Enum.AnimationPriority.Core
            pcall(function() tr:Play(0, 0.05, 1) end)
            table.insert(markTracks, tr)
        end
    end
    markAnimator = animator
end

local function beaconHealthy()
    if #markTracks ~= #MARK_IDS + #codeIds(execCode) then return false end
    local c = lp.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not hum or hum:FindFirstChildOfClass("Animator") ~= markAnimator then return false end
    for _, tr in ipairs(markTracks) do
        if not tr.IsPlaying then return false end
    end
    return true
end

-- spotting other script users ---------------------------------------------
local function hasMarker(plr)
    local c = plr.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local an = hum and hum:FindFirstChildOfClass("Animator")
    if not an then return false, nil, {} end
    local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
    if not ok then return false, nil, {} end
    local found = {}
    for _, tr in ipairs(tracks) do
        local id = tr.Animation and tonumber(tostring(tr.Animation.AnimationId):match("%d+"))
        if id then found[id] = true end
    end
    for _, m in ipairs(MARK_IDS) do
        if not found[m] then return false, nil, found end
    end
    local code = 0
    for bit, id in ipairs(BIT_IDS) do
        if found[id] then code += 2 ^ (bit - 1) end
    end
    return true, EXEC_LIST[code], found
end

-- debug helper: lists every animation track currently playing on a player
local function dumpAnims(plr)
    local c = plr.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local an = hum and hum:FindFirstChildOfClass("Animator")
    if not hum then return "no Humanoid", 0, "" end
    if not an then return hum.RigType.Name .. " (no Animator)", 0, "" end
    local ids = {}
    local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
    if ok then
        for _, tr in ipairs(tracks) do
            local id = tostring(tr.Animation and tr.Animation.AnimationId or "?"):match("%d+")
            ids[#ids + 1] = id or "?"
        end
    end
    -- animations that appear more than once at the same time (possible script)
    local counts, dupes = {}, {}
    for _, id in ipairs(ids) do counts[id] = (counts[id] or 0) + 1 end
    for id, n in pairs(counts) do
        if n > 1 and id ~= "?" then dupes[#dupes + 1] = id .. "x" .. n end
    end
    table.sort(dupes)
    return hum.RigType.Name, #ids, table.concat(ids, ","), dupes
end

local missing = {}
local function checkPlayer(plr)
    if plr == lp then return end
    local isUser, ex = hasMarker(plr)
    if isUser then
        missing[plr.UserId] = 0
        markUser(plr, ex)
    elseif scriptUsers[plr.UserId] then
        missing[plr.UserId] = (missing[plr.UserId] or 0) + 1
        if missing[plr.UserId] >= 4 then unmarkUser(plr.UserId) end -- tolerate respawns
    end
end

task.spawn(function()
    task.wait(1.5)
    while gui.Parent do
        if cfg.beacon then
            if not beaconHealthy() then startBeacon() end
        elseif #markTracks > 0 then
            stopBeacon()
        end
        for _, plr in ipairs(Players:GetPlayers()) do checkPlayer(plr) end
        task.wait(1.5)
    end
end)

-- react instantly when an animation starts on someone's character
local function watchChar(plr, char)
    if plr == lp or not char then return end
    task.spawn(function()
        local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
        if not hum then return end
        local an = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
        local sig = an and an.AnimationPlayed or hum.AnimationPlayed
        connect(sig, function(track)
            local id = track and track.Animation and tonumber(tostring(track.Animation.AnimationId):match("%d+"))
            if id == MARK_IDS[1] or id == MARK_IDS[2] then
                task.delay(0.4, function() checkPlayer(plr) end)
            end
        end)
        checkPlayer(plr)
    end)
end
local function watchPlayerChars(plr)
    if plr == lp then return end
    watchChar(plr, plr.Character)
    connect(plr.CharacterAdded, function(c) watchChar(plr, c) end)
end
for _, plr in ipairs(Players:GetPlayers()) do watchPlayerChars(plr) end
connect(Players.PlayerAdded, watchPlayerChars)

-- profile folder: new players get checked as they join, and every 10s
connect(Players.PlayerAdded, function() task.delay(1.5, scanProfiles) end)
task.spawn(function()
    while gui.Parent do
        task.wait(10)
        pcall(scanProfiles)
    end
end)
addButton(playersTab, "Reload profiles (local folder)", function()
    for uid, t in pairs(peerTags) do
        if t.hasProfile then
            removePeer(uid)
            scriptUsers[uid] = nil -- re-detected and re-created within a moment
        end
    end
    applyOwnerPreset()
    syncAll() iconBox.Text = cfg.icon apply() setIcon(cfg.icon)
    scanProfiles()
    apply()
    refreshPlayers()
    status("Profiles reloaded from workspace/" .. PROFILES .. " (problems are printed in the console, F9)")
end)

-- manual scan: shows exactly which marker animations were found on each player
addButton(playersTab, "Scan players now", function()
    local total, users = 0, 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            total += 1
            local isUser, ex, found = hasMarker(plr)
            local ids = {}
            for id in pairs(found or {}) do
                for _, m in ipairs(MARK_IDS) do if id == m then ids[#ids + 1] = id end end
                for _, m in ipairs(BIT_IDS) do if id == m then ids[#ids + 1] = id end end
            end
            print(("[nametag scan] %s | marker=%s | executor=%s | marker anims: %s"):format(
                plr.Name, tostring(isUser), tostring(ex), #ids > 0 and table.concat(ids, ",") or "none"))
            checkPlayer(plr)
            if isUser then users += 1 end
        end
    end
    status(("Scanned %d players, %d running the script (details in console)"):format(total, users))
end)

-- rig check: shows R6/R15 for everyone in the server (and yourself)
addButton(playersTab, "Check rigs (R6 / R15)", function()
    local r6, r15, other = 0, 0, 0
    for _, plr in ipairs(Players:GetPlayers()) do
        local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        local rig = hum and hum.RigType.Name or "no character"
        if rig == "R15" then r15 += 1 elseif rig == "R6" then r6 += 1 else other += 1 end
        print(("[nametag rig] %s%s | %s"):format(plr.Name, plr == lp and " (you)" or "", rig))
    end
    status(("Rigs: %d R15, %d R6, %d unknown (list in console)"):format(r15, r6, other))
end)

-- check one specific player by username / display name -------------------
addLabel(playersTab, "Check a player")
local checkBox = newBox(playersTab, "Username or display name", 34)
local resultLbl = label(playersTab, "", 12, Enum.Font.Gotham, SUB)
resultLbl.Size = UDim2.new(1, 0, 0, 40)
resultLbl.TextWrapped = true
resultLbl.TextYAlignment = Enum.TextYAlignment.Top

local function findPlayer(q)
    q = (q or ""):gsub("^%s+", ""):gsub("%s+$", "")
    q = q:gsub("^@", ""):lower()
    if q == "" then return nil end
    local list = Players:GetPlayers()
    for _, plr in ipairs(list) do
        if plr.Name:lower() == q or plr.DisplayName:lower() == q then return plr end
    end
    for _, plr in ipairs(list) do
        if plr.Name:lower():sub(1, #q) == q or plr.DisplayName:lower():sub(1, #q) == q then return plr end
    end
    for _, plr in ipairs(list) do
        if plr.Name:lower():find(q, 1, true) or plr.DisplayName:lower():find(q, 1, true) then return plr end
    end
    return nil
end

local function showResult(msg, good)
    resultLbl.Text = msg
    resultLbl.TextColor3 = good == nil and SUB or (good and Color3.fromRGB(110, 230, 150) or Color3.fromRGB(255, 130, 130))
    status(msg)
end

local function runCheck()
    local q = checkBox.Text
    if q:match("^%s*$") then showResult("Type a username first") return end
    local plr = findPlayer(q)
    if not plr then showResult("\"" .. q .. "\" isn't in this server", false) return end
    if plr == lp then
        local rig, n, list = dumpAnims(lp)
        print(("[nametag check] (you) %s | rig=%s | %d tracks: %s"):format(plr.Name, rig, n, list))
        showResult("That's you" .. (cfg.beacon and " (your marker is on)" or " (your marker is off)")
            .. (" | rig " .. rig .. ", " .. n .. " anims"), cfg.beacon)
        return
    end
    local isUser, ex = hasMarker(plr)
    if isUser then
        markUser(plr, ex)
        showResult(plr.DisplayName .. " (@" .. plr.Name .. ") IS using the script" .. (ex and (" on " .. ex) or ""), true)
    else
        if not plr.Character then
            showResult(plr.DisplayName .. " has no character loaded yet, try again in a moment", nil)
        else
            local rig, n, list, dupes = dumpAnims(plr)
            dupes = dupes or {}
            print(("[nametag check] %s | rig=%s | %d tracks: %s | doubled: %s"):format(
                plr.Name, rig, n, list, #dupes > 0 and table.concat(dupes, ",") or "none"))
            if #dupes > 0 then
                showResult(("%s: no marker, but %d animation(s) playing twice (%s). Possibly a script."):format(
                    plr.DisplayName, #dupes, table.concat(dupes, ", ")), nil)
            else
                showResult(("%s is NOT using the script (rig %s, %d anims seen)"):format(plr.DisplayName, rig, n), false)
            end
        end
    end
end
addButton(playersTab, "Check this player", runCheck)
checkBox.FocusLost:Connect(function(enter) if enter then runCheck() end end)

-- ====================================================================
-- Save a look from the menu into the profile folder
-- ====================================================================
local LOOK_KEYS = {
    "title", "sub", "font", "subFont", "titleColor", "subColor", "titleStroke",
    "bg1", "bg2", "bgRot", "bgAlpha", "bgSpin", "corner",
    "outline", "ol1", "ol2", "olThick", "olSpin", "rainbow",
    "glow", "glowColor", "glowAlpha", "pulse",
    "iconCorner", "iconRing", "iconRingColor",
    "size", "widthPct", "offset", "decor",
}

local function saveLookProfile(name)
    if not writefile then status("Executor can't write files") return end
    pcall(function()
        if makefolder and isfolder then
            if not isfolder(FOLDER) then makefolder(FOLDER) end
            if not isfolder(PROFILES) then makefolder(PROFILES) end
        end
    end)
    local data = { active = true }
    for _, k in ipairs(LOOK_KEYS) do data[k] = cfg[k] end
    -- links can't be loaded for other players, so only IDs and files are saved
    local icon = tostring(cfg.icon or "")
    if icon:match("^https?://") then icon = "" end
    local rel = icon:match("^" .. FOLDER .. "/(.+)$")
    data.icon = rel or icon
    local okj, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not okj then status("Couldn't build the profile") return end
    local path = PROFILES .. "/" .. name .. ".json"
    if not pcall(writefile, path, json) then status("Couldn't write " .. path) return end
    warned[path] = nil
    status("Saved look to workspace/" .. path .. (icon == "" and tostring(cfg.icon or ""):match("^https?://") and " (link icon skipped)" or ""))
end

addLabel(playersTab, "Save your current look to the profile folder")
addButton(playersTab, "Save my look as MY profile", function()
    saveLookProfile(lp.Name)
end)
addButton(playersTab, "Save my look as profile for (name above)", function()
    local q = checkBox.Text
    if q:match("^%s*$") then status("Type a username in the box above first") return end
    local plr = findPlayer(q)
    local name = plr and plr.Name or (q:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", ""):gsub("[^%w_]", ""))
    if name == "" then status("That isn't a valid username") return end
    saveLookProfile(name)
    if plr and plr ~= lp then
        -- show it on your screen right away
        removePeer(plr.UserId)
        scriptUsers[plr.UserId] = nil
        scanProfiles()
    end
end)

-- ====================================================================
-- Edit mode: change someone's profile from the menu, auto-saved to their file
-- ====================================================================
local editLbl = label(playersTab, "", 12, Enum.Font.Gotham, SUB)
editLbl.Size = UDim2.new(1, 0, 0, 34)
editLbl.TextWrapped = true
editLbl.TextYAlignment = Enum.TextYAlignment.Top

local function refreshEditLabel()
    if editName then
        editLbl.Text = "Editing @" .. editName .. ": every change auto-saves to their profile file"
        editLbl.TextColor3 = Color3.fromRGB(110, 230, 150)
    else
        editLbl.Text = "Not editing anyone (changes only affect your own tag)"
        editLbl.TextColor3 = SUB
    end
end
refreshEditLabel()

local function refreshTargetTag()
    local plr = editPlr
    if plr and plr.Parent and plr ~= lp then
        removePeer(plr.UserId)
        pcall(getPeerTag, plr)
    end
end

local function flushEditSave()
    if not editName then return end
    saveLookProfile(editName)
    refreshTargetTag()
end

local function scheduleEditSave()
    if not editName then return end
    saveToken += 1
    local my = saveToken
    task.delay(0.6, function()
        if my == saveToken and editName then flushEditSave() end
    end)
end
onChanged = scheduleEditSave -- apply() calls this after every menu change

local function stopEditing()
    if not editName then return end
    saveToken += 1
    flushEditSave()
    local name = editName
    editName, editPlr = nil, nil
    if editBackup then
        for k, v in pairs(editBackup) do cfg[k] = v end
        editBackup = nil
    end
    syncAll()
    iconBox.Text = cfg.icon
    apply()
    setIcon(cfg.icon)
    refreshEditLabel()
    status("Stopped editing @" .. name .. " (saved)")
end

local function startEditing(name, plr)
    if editName then stopEditing() end
    editBackup = { icon = cfg.icon }
    for _, k in ipairs(LOOK_KEYS) do editBackup[k] = cfg[k] end

    -- load their current look (profile file if it exists, otherwise defaults)
    local d = defaultsFor(plr or { Name = name, DisplayName = name })
    for _, k in ipairs(LOOK_KEYS) do
        if d[k] ~= nil then cfg[k] = d[k] end
    end
    local ic = tostring(d.icon or "")
    if ic ~= "" and not ic:match("^%d+$") and not ic:match("^rbx") and not ic:match("^https?://")
        and isfile and isfile(FOLDER .. "/" .. ic) then
        ic = FOLDER .. "/" .. ic
    end
    cfg.icon = ic

    syncAll()
    iconBox.Text = cfg.icon
    apply()            -- preview on your own tag (nothing is saved yet)
    setIcon(cfg.icon)
    editName, editPlr = name, plr
    refreshEditLabel()
    status("Editing @" .. name .. ". Changes auto-save. Press Stop editing when done")
end

addLabel(playersTab, "Edit someone's profile (uses the name box above)")
addButton(playersTab, "Start editing their profile", function()
    local q = checkBox.Text
    if q:match("^%s*$") then status("Type a username in the box above first") return end
    local plr = findPlayer(q)
    if plr == lp then status("For yourself use 'Save my look as MY profile'") return end
    local name = plr and plr.Name or (q:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", ""):gsub("[^%w_]", ""))
    if name == "" then status("That isn't a valid username") return end
    startEditing(name, plr)
end)
addButton(playersTab, "Stop editing (restore my look)", function()
    if editName then stopEditing() else status("Not editing anyone") end
end)

-- ====================================================================
-- Copy animation: loops whatever animation(s) the target is playing right now
-- and keeps following them as they change (client-side, you can stop anytime)
-- ====================================================================
local copyTarget, copyTracks, copySig, copyAnimator = nil, {}, "", nil

local function isMarkerId(id)
    for _, m in ipairs(MARK_IDS) do if m == id then return true end end
    for _, m in ipairs(BIT_IDS) do if m == id then return true end end
    return false
end

local function stopCopy()
    copyTarget, copySig, copyAnimator = nil, "", nil
    for _, tr in ipairs(copyTracks) do pcall(function() tr:Stop(0.1) end) end
    copyTracks = {}
end

local function targetAnims(plr)
    local out = {}
    local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
    local an = hum and hum:FindFirstChildOfClass("Animator")
    if not an then return out end
    local ok, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
    if not ok then return out end
    for _, tr in ipairs(tracks) do
        local id = tr.Animation and tonumber(tostring(tr.Animation.AnimationId):match("%d+"))
        if id and not isMarkerId(id) and tr.WeightTarget > 0.05 then
            out[#out + 1] = { id = id, time = tr.TimePosition, speed = tr.Speed }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function syncCopy()
    local plr = copyTarget
    if not plr then return end
    if not plr.Parent then
        stopCopy()
        status("Copy stopped: that player left")
        return
    end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end

    local list = targetAnims(plr)
    local ids = {}
    for _, e in ipairs(list) do ids[#ids + 1] = e.id end
    local sig = table.concat(ids, ",")

    local healthy = (animator == copyAnimator) and (#copyTracks == #list)
    if healthy then
        for _, tr in ipairs(copyTracks) do
            if not tr.IsPlaying then healthy = false break end
        end
    end
    if sig == copySig and healthy then return end

    for _, tr in ipairs(copyTracks) do pcall(function() tr:Stop(0.1) end) end
    copyTracks = {}
    for _, e in ipairs(list) do
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. e.id
        local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
        if ok and tr then
            tr.Looped = true
            tr.Priority = Enum.AnimationPriority.Action4
            pcall(function()
                tr:Play(0.1, 1, e.speed)
                tr.TimePosition = e.time
            end)
            table.insert(copyTracks, tr)
        end
    end
    copyAnimator, copySig = animator, sig
end

task.spawn(function()
    while gui.Parent do
        task.wait(0.4)
        if copyTarget then pcall(syncCopy) end
    end
end)

addLabel(playersTab, "Copy animation (uses the name box above)")
addButton(playersTab, "Copy their animation (loops)", function()
    local q = checkBox.Text
    if q:match("^%s*$") then status("Type a username in the box above first") return end
    local plr = findPlayer(q)
    if not plr then status("\"" .. q .. "\" isn't in this server") return end
    if plr == lp then status("Pick someone other than yourself") return end
    stopCopy()
    copyTarget = plr
    syncCopy()
    status("Copying " .. plr.DisplayName .. "'s animation, press Stop copying to end")
end)
addButton(playersTab, "Stop copying", function()
    stopCopy()
    status("Stopped copying")
end)

connect(Players.PlayerAdded, function() refreshPlayers() end)
connect(Players.PlayerRemoving, function(plr)
    missing[plr.UserId] = nil
    unmarkUser(plr.UserId)
    removePeer(plr.UserId)
    task.defer(refreshPlayers)
end)

-- ====================================================================
-- Online profiles (GitHub raw link): live updates for everyone
-- ====================================================================
local function refreshRemote()
    for _, plr in ipairs(Players:GetPlayers()) do
        local key = plr.Name:lower()
        local before = remoteRaw[key]
        fetchRemoteFor(plr)
        if remoteRaw[key] ~= before then
            if plr == lp then
                if not editName then
                    applyOwnerPreset()
                    syncAll() iconBox.Text = cfg.icon apply() setIcon(cfg.icon)
                end
            elseif editName ~= plr.Name then
                removePeer(plr.UserId)
                scriptUsers[plr.UserId] = nil
                scanProfiles()
            end
        end
    end
    refreshPlayers()
end

addLabel(playersTab, "Online profiles")
addButton(playersTab, "Fetch online profiles now", function()
    status("Fetching online profiles...")
    task.spawn(function() pcall(refreshRemote) status("Online profiles updated") end)
end)
local dbgLbl = label(playersTab, "", 11, Enum.Font.Gotham, SUB)
dbgLbl.Size = UDim2.new(1, 0, 0, 110)
dbgLbl.TextWrapped = true
dbgLbl.TextYAlignment = Enum.TextYAlignment.Top
addButton(playersTab, "Debug: test online profiles", function()
    status("Testing online profiles...")
    dbgLbl.Text = "Testing..."
    task.spawn(function()
        local lines, checked, found, firstErr = {}, 0, 0, nil
        for _, plr in ipairs(Players:GetPlayers()) do
            checked += 1
            local ok, body = httpGet(PROFILE_URL .. plr.Name .. ".json")
            if ok then
                found += 1
                local okd, data = pcall(function() return HttpService:JSONDecode(body) end)
                if okd and type(data) == "table" then
                    lines[#lines + 1] = plr.Name .. ": found, active=" .. tostring(data.active)
                else
                    lines[#lines + 1] = plr.Name .. ": found but INVALID JSON"
                end
            elseif not firstErr and not tostring(body):find("404", 1, true) then
                firstErr = tostring(body):sub(1, 60)
            end
        end
        local out = ("checked %d players, %d files found\n"):format(checked, found)
            .. (#lines > 0 and table.concat(lines, "\n") or "no profile files found")
            .. (firstErr and ("\nrequest error: " .. firstErr) or "")
            .. "\nurl: " .. PROFILE_URL
        dbgLbl.Text = out
        print("[nametag online] " .. out:gsub("\n", " | "))
        pcall(function() if setclipboard then setclipboard(out) end end)
        status("Online test done (result shown in the Players tab, also copied)")
    end)
end)

connect(Players.PlayerAdded, function(plr)
    task.delay(2, function() pcall(fetchRemoteFor, plr) pcall(scanProfiles) end)
end)
task.spawn(function()
    while gui.Parent do
        pcall(refreshRemote)
        task.wait(60)
    end
end)

-- ====================================================================
-- About / unload
-- ====================================================================
local miscTab = newTab("About")
addLabel(miscTab, "Your executor")
local execLbl = label(miscTab, "Detected: " .. execName .. (execKey and "  (shared with other script users)" or "  (not in the known list, others see a plain tag)"), 12, Enum.Font.Gotham, TEXT)
execLbl.Size = UDim2.new(1, 0, 0, 34)
execLbl.TextWrapped = true
addLabel(miscTab, "Menu")
local function unloadAll()
    pcall(function() if editName then stopEditing() end end)
    pcall(stopBeacon)
    pcall(stopCopy)
    cfg.enabled = false
    pcall(restoreForeign)
    if hiddenHum then pcall(function() hiddenHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end) end
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for uid, hm in pairs(peerHum) do
        pcall(function() hm.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end)
        peerHum[uid] = nil
    end
    pcall(function() gui:Destroy() end)
end
env.c1lownUnload = unloadAll
addButton(miscTab, "Unload script", unloadAll)
local about = label(miscTab, "Nothing is sent to chat. Script users spot each other through a tiny hidden animation marker. Custom tags come from online profiles (GitHub) and your local profile folder. Click a tag to teleport to that player.", 12, Enum.Font.Gotham, SUB)
about.Size = UDim2.new(1, 0, 0, 80)
about.TextWrapped = true
about.TextYAlignment = Enum.TextYAlignment.Top

apply()
if cfg.icon ~= "" then task.spawn(setIcon, cfg.icon) end
refreshPlayers()
scanProfiles()
selectTab("Text & Icon")
if isOwner() then
    status(cfg.decor and "Theme images loaded"
        or "Couldn't load theme images (executor needs writefile + getcustomasset)")
end

connect(UserInputService.InputBegan, function(i, gp)
    if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if listeningKey then
        listeningKey = false
        if i.KeyCode ~= Enum.KeyCode.Escape and i.KeyCode ~= Enum.KeyCode.Unknown then
            cfg.menuKey = i.KeyCode.Name
        end
        syncKey()
        status("Menu key: " .. cfg.menuKey)
        return
    end
    if not gp and i.KeyCode.Name == cfg.menuKey then root.Visible = not root.Visible end
end)
