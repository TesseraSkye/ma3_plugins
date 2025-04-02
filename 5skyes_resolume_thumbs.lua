-- This MA3 plugin populates the console's image pool with thumbnails from resolume using redsolume's REST API and websocket.
-- for more info on the webserver, visit https://resolume.com/support/restapi.
--
-- This plug utilizes async arbitrary code execution inspired by Adam Pinter's (adam.pinter@apox.hu) ping plugin, and therefore..
-- This code is licensed under an adapted version of the Creative Commons Attribution-NonCommercial 4.0 International
-- (CC BY-NC 4.0) license. It permits users to modify and use the software for personal or professional (for-profit)
-- purposes, provided that the software itself is not sold, sublicensed, or redistributed for profit. The copyright
-- notice must always be retained in all copies or derivative works. This software is provided "as-is," without warranty
-- of any kind. You can read the full license at https://github.com/apoxhu/MA3_lua_snippets/blob/main/LICENSE.md

-- //


function CMDAsync(async_cmd, isDebug)
    local tmpfile = GetPath(Enums.PathType.Temp)-- os.tmpname() returns empty string on console !
    tmpfile = tmpfile .. "/5s_Res_th_" .. tostring(os.clock()):gsub('%.', '')
    Echo("Logs for this execution writing to " .. tmpfile)
    Printf("Logs for this execution writing to " .. tmpfile)
    Printf("")

    os.execute('mkdir -p "' .. tmpfile .. '"') -- writes a directory in which logs are stored and execution is sandboxed.

    if HostOS() == 'Windows' then
        local f = io.open(tmpfile .. '/x.bat', 'w')
        f:write(async_cmd .. "\n@echo %ERRORLEVEL% > return_value.txt\n@exit")
        f:close()
        os.execute('cd /d ' .. tmpfile .. ' && start /B x.bat > output.txt') -- writes bat file with commands and logs the response
    else
        local f = io.open(tmpfile .. '/x.sh', 'w')
        f:write("#!/bin/bash\n" .. async_cmd .. "\necho $? > return_value.txt\nexit")
        f:close()
        os.execute('cd ' .. tmpfile .. ' && chmod +x x.sh && ./x.sh > output.txt 2>&1 &') -- writes shell file with commands and logs the response
    end

    local outFile = io.open(tmpfile .. '/output.txt', "r")
    local finished = false

    return {
        isRunning = function(self)
            return self:getResult() == true
        end,
        getResult = function(self)
            -- this returns the process result. If nil, the process is still running!
            local file = io.open(tmpfile .. '/return_value.txt', "r")
            if not file then
                return true
            end
            local result = file:read("*a")
            file:close()
            return result
        end,
        getLine = function(self)
            if finished then
                return nil
            end
            if not outFile then
                -- file did not open yet, try again...
                outFile = io.open(tmpfile .. '/output.txt', "r")
            end

            if not outFile then
                return false
            end

            local lastPosition = outFile:seek() or 0
            local newEndPosition = outFile:seek("end") or 0
            outFile:seek("set", lastPosition)
            local bytesToRead = newEndPosition - lastPosition

            if bytesToRead == 0 then
                return false
            end
            local content, err = outFile:read(bytesToRead)

            if not self:isRunning() then
                finished = true;
                io.close(outFile);
                outFile = nil
            end

            return content, err
        end,
        free = function()
            if outFile then
                io.close(outFile)
                outFile = nil
            end
            local closeMe = "Y"
            if (isDebug) then 
                closeMe = TextInput("Clean up temp files? [(Y)/N]") or "Y"
            end
            if (closeMe ~= "N" or "n" or "no" or "NO" or "No") then
                if isDebug then Printf("") Printf("Leaving temp files in place..") Printf("") end
            else
                if isDebug then Printf("") Printf("Cleaning up temp files...") Printf("") end
                if HostOS() == 'Windows' then
                    os.execute('rmdir /s /q "' .. tmpfile .. '"')
                else
                    os.execute('rm -rf "' .. tmpfile .. '"')
                end
            end
        end
    }
end

function BuildThumbs (sLocal,sDir,api,lay,clip,prefix,suffix,c_atribs) -- builds command string for thumbs. 
    local l_cmd = ""
    local s_lThumbs = sLocal .. sDir
    local l_clipTarget = "\"" .. s_lThumbs .. "/" .. prefix .. "L" .. lay .. "C" .. clip .. suffix .. "\""
            local l_clipAPI = api .. "/composition/layers/" .. lay .. "/clips/" .. clip
            if FileExists(l_clipTarget) ~= true then -- if a thumbnail does not already exist locally
                l_cmd = l_cmd .. "echo \"[get] L" .. lay .. "C" .. clip .. "\"\n"
                -- check in bash world if remote clip is using a default thumbnail. This is kinda brutal.. a json parser would be cool. Might break on linux.
                l_cmd = l_cmd .. "curl " .. c_atribs .. l_clipAPI.. " " -- returns the clip's properties..
                l_cmd = l_cmd .. "| findstr /C:\"/composition/thumbnail/dummy\" " -- then pipes those properties into a string search for dummy thumb usage.
                l_cmd = l_cmd .. "&& echo \"Dummy thumb detected, rerouting..\" " -- if it finds them...
                l_cmd = l_cmd .. "&& copy " .. s_lThumbs .. "/res_default_thumb" .. suffix .. " " .. l_clipTarget .. " " -- ... do a local copy instead of streaming
                l_cmd = l_cmd .. "|| curl " .. c_atribs .. "-o " .. l_clipTarget .. l_clipAPI .. "/thumbnail" .. "\n" -- if not local, stream it in.
            -- else -- if the thumbnail *IS* stored locally
                --check to see how old it is. FEATUER NYI, TODO . Will curently overwrite if unless it's a dummy.
            end
    return (l_cmd)
end

return function ()
    Printf("++++++++ + +++++ + ++ + ++++++=||=++++++ + ++ + +++++++ + ++++++")
    Printf("+ +++++++ +++++++++ ++++ ++ PLUG START ++ ++++ +++++++++ +++++ +")
    Printf("++++++++ + +++++ + ++ + ++++++=||=++++++ + ++ + +++++++ + ++++++")
    Printf("")
    Printf("+ ++++ +++++++++ ++++ + SCRIPT VARIABLES + ++++ +++++++++ ++++ +")
    Printf("")
    
    -- 
    --|||||||||||||||||||
    -- ==================
    -- Script Variables !
    -- ==================
    --|||||||||||||||||||
    --
    -- ===============================
    -- script hard statics (don't change !)
    -- ===============================
    local ma_pathImage = GetPath("images")
    -- ===========
    -- debug tools
    -- ===========
    local isDebug = true -- Should the script provide verbose debug info ?
    -- ===================
    -- script soft statics
    -- ===================
    local wt = ma_pathImage -- assigns the dynamic write target to our MA images hard-folder.
    local wt_suffix = "/resolume/thumbnails"
    local wt_thumb = wt .. wt_suffix
    local fileThumbPrefix = "5s_rt_"
    local fileThumbSuffix = ".png"
    if(isDebug) then Printf("Host OS is: " .. HostOS()) end
    local webserverIP = TextInput("Resolume Webserver IP")
    if webserverIP == nil or "" then  -- Checks against host for default blank assignment. (has TODO)
        if(isDebug) then Printf("No IP defined, using default..") end
        if HostOS() == 'Windows' then
            webserverIP = "127.0.0.1" -- Defaults to localhost for onPC use. This will fail on consoles, so failing to provide an IP will close the plugin.
            --else
            --TODO ------- Close Plugin
        end
    end
    -- webserverIP should be checked against curent IP range on all adapters and fail if it couldn't be written to. TODO.
    local webserverPORT = TextInput("Webserver port - def. 8080")
    if webserverPORT == nil or "" then webserverPORT = "8080" if(isDebug) then Printf("No port defined, using default..") end end
    local ws = "http://" .. webserverIP .. ":" .. webserverPORT
    local wsapi = ws .. "/api/v1"
    if(isDebug) then Printf("API is: " .. wsapi) end
    local c_get_atr = "-v " -- default curl options for gets,,, needs output
    -- ===========
    -- Script Vars
    -- ===========
    local t_cmd = "" -- prealoc buffer for thumb command
    -- =========================
    -- Resolume config variables
    -- =========================
    local rsl_layerStart = 1 -- rest API expects numbers starting at 1, not zero.
    local rsl_layerEnd = 2 -- end inclusive
    local rsl_clipStart = 1
    local rsl_clipEnd = 2
    -- ===================
    -- MA config variables
    -- ===================
    -- should be banked one number prior to first image.... ie to write images starting at 1101 should be written as 1000 for layer 1 clip 1. Ganging is 100 per layer, starting wit clip numbers.
    local ma_startingImageOffset = 1000
    -- local image directory contents
    local ma_dirContents = DirList(wt) -- contents of write target directory.. should contain [./wt_suffix]
    local ma_thumbContents = DirList(wt_thumb) -- contents of thumb directory.. should contain thumbs.
    --
    -- |||||||||||||||
    -- ===============
    -- Program Start !
    -- ===============
    -- |||||||||||||||
    -- 
    -- =========
    -- commands!
    -- =========
    --- --- {{{TO DO }}} --- ---  do a ping test here
    --- 
    Printf("")
    Printf("+ +++ +++++++++ ++ + THUMBNAIL LOCALIZATION + ++ +++++++++ +++ +")
    Printf("")
    Printf("Attempting to bake command...")
    Printf("Checking for resolume thumbs directory (" .. "\"" .. "." .. wt_suffix .. "\"" .. ") inside " .. "\"" .. wt .."\"")
    local f_hasDirThumb = FileExists(wt_thumb) -- set flag for presence of write target thumbs subdirectory..
    if(isDebug) then
        Printf("does \"" .. wt_thumb .. "\" exist?")
        if (f_hasDirThumb) then
            Printf("    Yep!")
            Printf("    Contains...")
            for _, item in pairs(ma_thumbContents) do
                if(isDebug) then
                    Printf("    + " .. item["name"])
                end
            end
        else
            Printf("    Nope.")
        end
    end
    if(f_hasDirThumb) ~= true then
        t_cmd = t_cmd .. "echo Resolume directory doesn not exist, writing...\n" 
        t_cmd = t_cmd .. "mkdir \"" .. wt .. "/resolume" .. "\"\n" 
        t_cmd = t_cmd .. "mkdir \"" .. wt .. "/resolume/thumbnails" .. "\"\n" 
    end
    t_cmd = t_cmd .. "echo Checking if default clip icon is in images folder...\n" 
    --
    if FileExists("\"" .. wt_thumb .. "/res_default_thumb" .. fileThumbSuffix .. "\"") == true then -- checks if default png is in thumbnail directory..
        Printf("Default thumbnail found, using local file ..")
    else -- and if it isn't..
        t_cmd = t_cmd .. "curl " .. c_get_atr .. "-o " .. "\"" .. wt_thumb .. "/res_default_thumb" .. fileThumbSuffix .. "\" " .. wsapi .. "/composition/thumbnail/dummy\n"
        Printf("Default thumbnail not stored locally, fetch added to bake ..")
    end
    --
    t_cmd = t_cmd .. "echo iterating through resolume clips for webserver at " .. ws .. "\n"
    if (isDebug) then Printf("Appending clips ".. rsl_clipStart .. " thru " .. rsl_clipEnd .. " on layers " .. rsl_layerStart .. " thru " .. rsl_layerEnd .. ".") end
    for iLay = rsl_layerStart, rsl_layerEnd do
        t_cmd = t_cmd .. "echo Writing thumbs for layer " .. iLay .. "\n"
        for iClip = rsl_clipStart, rsl_clipEnd do
            local thisThumb = BuildThumbs(wt,wt_suffix,wsapi,iLay,iClip,fileThumbPrefix,fileThumbSuffix,c_get_atr)
            t_cmd = t_cmd .. thisThumb
            if (isDebug) then Printf("L" .. iLay .. " C" .. iClip .. " appended.") end
            if (isDebug) then
                for line in thisThumb:gmatch("[^\n]+") do
                    Printf(line)
                end
            end
        end
    end
    t_cmd = t_cmd .. "Clips ".. rsl_clipStart .. " thru " .. rsl_clipEnd .. " on layers " .. rsl_layerStart .. " thru " .. rsl_layerEnd .. " imported.\n"
    local command = t_cmd .. "\n" .. "" -- Concat any other commands....
    
    Printf("Command Baked.")
    Printf("")
    if (isDebug) then
        for line in command:gmatch("[^\n]+") do
            Printf(line)
        end
    end
    Printf("Attempting to run baked command.")
    Printf("\n")
    
    local cmdObj = CMDAsync(command, isDebug)
    local result
    coroutine.yield(0.5) -- pause half a second... these async requests might take a while, as this could be tens mb for a decently sized comp.
                         -- TODO some testing for delay and add compensation. Preferably it'd be async with proper handlers and a non-blocking callback.


    

    -- wait for lines from commands...
    repeat
        result = cmdObj:getLine()
        if result then
            for line in result:gmatch("[^\n]+") do
                Printf(line .. "\n")
            end
            -- for _, text in ipairs(texts) do
            --     if (IsObjectValid(text)) then
            --         text.Text = text.Text .. result
            --     end
            -- end
        end
        coroutine.yield(0.1)
    until result == nil

    cmdObj:free()
    Printf("")
    Printf("++++++++ + +++++ + ++ + +++++||+++++++++ + ++ + +++++++ + ++++++")
    Printf("+ +++++++ +++++++ ++++ ++ CMD  RESULTS ++ ++++ +++++++++ +++++ +")
    Printf("++++++++ + +++++ + ++ + +++++||+++++++++ + ++ + +++++++ + ++++++")
    Printf("")
    Printf("Command handler should be free...")
    Printf("Thumbnails should be aquired.")
    Printf("Check " .. "\"" .. wt_thumb .. "\"" .. " " .. "to validate.")
    
    -- If everything ran succesfully, start binding image files to image pool items 
    -- for sLay = rsl_layerStart, rsl_layerEnd do
        
    --     for sClip = rsl_clipStart, rsl_clipEnd do
    --         Printf("[set] L" .. sLay .. "C" .. sClip .. "\n")
    --         -- 
    --     end
    -- end

    -- local l_ma_undo = CreateUndo("Ingest Res L" .. iLay .. " Thumbs")
    -- Cmd("Import Image \"Images\".".. ma_startingImageOffset .. " /File \"rgbluma 2 test.png.xml\" /Path \"C:/ProgramData/MALightingTechnology/gma3_library/media/images\" /NoConfirmation", l_ma_undo)
    --     ma_startingImageOffset = ma_startingImageOffset + 1
    --     local undoSucess = CloseUndo(l_ma_undo)
end