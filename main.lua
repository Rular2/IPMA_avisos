-- Require libraries
local widget = require("widget")
local json = require("json")
local network = require("network")

-- Set up variables
local currentLatitude = nil
local currentLongitude = nil
local currentDistrict = "Unknown"
local isSafeDistrict = false
local safetyData = {}

-- Portuguese districts data with approximate boundaries and IPMA area codes
-- Format: {name, minLat, maxLat, minLong, maxLong, ipmaCode}
local districts = {
    {name = "Lisboa", minLat = 38.6, maxLat = 39.1, minLong = -9.5, maxLong = -8.8, ipmaCode = "1110600", warningAreaCode = "LSB"},
    {name = "Porto", minLat = 41.0, maxLat = 41.4, minLong = -8.8, maxLong = -8.1, ipmaCode = "1131200", warningAreaCode = "PTO"},
    {name = "Faro", minLat = 36.8, maxLat = 37.6, minLong = -9.0, maxLong = -7.3, ipmaCode = "1080500", warningAreaCode = "FAR"},
    {name = "Braga", minLat = 41.3, maxLat = 41.8, minLong = -8.6, maxLong = -7.8, ipmaCode = "1030300", warningAreaCode = "BRG"},
    {name = "Coimbra", minLat = 39.9, maxLat = 40.4, minLong = -8.9, maxLong = -7.8, ipmaCode = "1060300", warningAreaCode = "CBR"},
    {name = "Setúbal", minLat = 37.8, maxLat = 38.8, minLong = -9.2, maxLong = -8.2, ipmaCode = "1151200", warningAreaCode = "STB"},
    {name = "Aveiro", minLat = 40.4, maxLat = 41.0, minLong = -8.8, maxLong = -8.0, ipmaCode = "1010500", warningAreaCode = "AVR"},
    {name = "Leiria", minLat = 39.4, maxLat = 40.0, minLong = -9.2, maxLong = -8.4, ipmaCode = "1100900", warningAreaCode = "LRA"},
    {name = "Santarém", minLat = 38.8, maxLat = 39.7, minLong = -8.9, maxLong = -7.8, ipmaCode = "1141600", warningAreaCode = "STR"},
    {name = "Viseu", minLat = 40.5, maxLat = 41.2, minLong = -8.1, maxLong = -7.2, ipmaCode = "1182300", warningAreaCode = "VIS"},
    {name = "Vila Real", minLat = 41.1, maxLat = 41.8, minLong = -8.0, maxLong = -7.1, ipmaCode = "VRL1171400", warningAreaCode = "VRL"},
    {name = "Bragança", minLat = 41.3, maxLat = 41.9, minLong = -7.2, maxLong = -6.2, ipmaCode = "1040200", warningAreaCode = "BGC"},
    {name = "Évora", minLat = 38.2, maxLat = 38.9, minLong = -8.5, maxLong = -7.1, ipmaCode = "1070500", warningAreaCode = "EVR"},
    {name = "Guarda", minLat = 40.2, maxLat = 41.0, minLong = -7.6, maxLong = -6.9, ipmaCode = "1090700", warningAreaCode = "GDA"},
    {name = "Beja", minLat = 37.5, maxLat = 38.3, minLong = -8.5, maxLong = -7.0, ipmaCode = "1020500", warningAreaCode = "BJA"},
    {name = "Castelo Branco", minLat = 39.5, maxLat = 40.4, minLong = -8.0, maxLong = -6.8, ipmaCode = "1050200", warningAreaCode = "CBR"},
    {name = "Portalegre", minLat = 38.8, maxLat = 39.5, minLong = -8.0, maxLong = -7.1, ipmaCode = "1121400", warningAreaCode = "PTG"},
    {name = "Viana do Castelo", minLat = 41.5, maxLat = 42.1, minLong = -8.9, maxLong = -8.1, ipmaCode = "1160900", warningAreaCode = "VCT"}
}


-- Storage for warning data
local warningData = {}

-- UI elements declaration
local statusText
local locationText
local districtText
local safetyText
local awarenessText

-- Helper function to parse ISO time format used by IPMA
function parseISOTime(isoTime)
    if not isoTime then return 0 end
    
    -- Pattern to match ISO 8601 format: "2025-03-20T21:46:00"
    local year, month, day, hour, min, sec = isoTime:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    
    if not year then return 0 end
    
    -- Convert to os.time format (table with year, month, day, etc.)
    local timeTable = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    }
    
    return os.time(timeTable)
end

-- Helper function to find which district contains the given coordinates and return its warning area code
local function findDistrict(lat, long)
    for i, district in ipairs(districts) do
        if lat >= district.minLat and lat <= district.maxLat and
           long >= district.minLong and long <= district.maxLong then
            -- Return district name, its ipmaCode, and warning area code
            return district.name, district.ipmaCode, district.warningAreaCode
        end
    end
    return "\nOutside known area", nil, nil
end

-- Fetch IPMA warning data
local function fetchIPMAWarnings(onComplete)
    if statusText then
        statusText.text = "Fetching warning data..."
    end
    
    -- IPMA Warnings API URL
    local apiURL = "https://api.ipma.pt/open-data/forecast/warnings/warnings_www.json"
    
    print("Requesting warnings data from: " .. apiURL)
    
    -- Network request
    network.request(apiURL, "GET", function(event)
        if event.isError then
            print("Network error: " .. tostring(event.response))
            if statusText then
                statusText.text = "Network error getting warning data"
            end
            if onComplete then onComplete(false) end
            return
        end
        
        print("Response received, length: " .. string.len(event.response))
        
        -- Parse JSON response
        local success, response = pcall(json.decode, event.response)
        
        if not success then
            print("JSON parsing error: " .. tostring(response))
            if statusText then
                statusText.text = "Invalid JSON response"
            end
            if onComplete then onComplete(false) end
            return
        end
        
        -- Clear existing warning data
        warningData = {}
        
        -- Process and organize warning data by area code
        for _, warning in ipairs(response) do
            local areaCode = warning.idAreaAviso
            
            if areaCode then
                -- Initialize area if needed
                if not warningData[areaCode] then
                    warningData[areaCode] = {}
                end
                
                -- Add this warning to the area
                table.insert(warningData[areaCode], warning)
            end
        end
        
        if statusText then
            statusText.text = "Warning data updated"
        end
        
        if onComplete then onComplete(true) end
    end)
end

local function initializeApp()
    if statusText then
        statusText.text = "Initializing app..."
    end
    
    -- Fetch initial warning data from the IPMA API
    fetchIPMAWarnings(function(success)
        if success then
            if statusText then
                statusText.text = "Ready - Tap Simulate or Start GPS. \nMake sure GPS is always on!"
            end
        else
            if statusText then
                statusText.text = "Warning: Could not fetch initial data"
            end
        end
    end)
end


local function isDistrictSafe(warningAreaCode)
    if not warningAreaCode then
        return false, "Not applicable"
    elseif not warningData[warningAreaCode] then
        return true, "No active warnings for this area"  -- Changed to true since no warnings means safe
    end
    
    local areaWarnings = warningData[warningAreaCode]
    local currentTime = os.time()
    local highestWarningLevel = "green"
    local warningText = "No active warnings"
    
    -- Check for active warnings
    for _, warning in ipairs(areaWarnings) do
        -- Parse start and end times from warning
        local startTime = parseISOTime(warning.startTime) 
        local endTime = parseISOTime(warning.endTime)   
        
        -- Check if warning is currently active
        if currentTime >= startTime and currentTime <= endTime then
            local level = warning.awarenessLevelID
            
            -- Update highest warning level (orange/red are unsafe, yellow/green are safe)
            if level == "red" then
                highestWarningLevel = "red"
                warningText = warning.awarenessTypeName
            elseif level == "orange" then
                highestWarningLevel = "orange"
                warningText = warning.awarenessTypeName
            elseif level == "yellow" then
                highestWarningLevel = "yellow"
                warningText = warning.awarenessTypeName
            elseif level == "green" then
                highestWarningLevel = 'green'
                warningText = "Not applicable"
            end
        end
    end
    
    -- Determine safety based on highest warning level
    -- Only red and orange are considered unsafe
    local isSafe = (highestWarningLevel ~= "red" and highestWarningLevel ~= "orange")
    
    return isSafe, warningText
end

-- Function to fetch IPMA data for a district
local function fetchIPMAData(ipmaCode, onComplete)
    if not ipmaCode then
        if onComplete then onComplete(false) end
        return
    end
    
    if statusText then
        statusText.text = "Fetching safety data..."
    end
    
    -- IPMA API URL following the successful PHP format
    local apiURL = "https://api.ipma.pt/open-data/forecast/meteorology/cities/daily/" .. ipmaCode .. ".json"
    
    print("Requesting data from: " .. apiURL)
    
    -- Network request
    network.request(apiURL, "GET", function(event)
        if event.isError then
            print("Network error: " .. tostring(event.response))
            if statusText then
                statusText.text = "Network error getting safety data"
            end
            if onComplete then onComplete(false) end
            return
        end
        
        print("Response received, length: " .. string.len(event.response))
        
        -- Parse JSON response
        local success, response = pcall(json.decode, event.response)
        
        if not success then
            print("JSON parsing error: " .. tostring(response))
            if statusText then
                statusText.text = "Invalid JSON response"
            end
            if onComplete then onComplete(false) end
            return
        end
        
        -- Debug the response structure
        print("Response structure: ", json.encode(response))
        
        -- Check for valid response structure properly
        if not response then
            print("Invalid response structure: nil response")
            if statusText then
                statusText.text = "No safety data available"
            end
            if onComplete then onComplete(false) end
            return
        end
        
        -- Store response data even if it doesn't match expected structure
        safetyData[ipmaCode] = response
        
        if statusText then
            statusText.text = "Safety data updated"
        end
        
        if onComplete then onComplete(true) end
    end)
end

local function updateLocationDisplay(latitude, longitude, district, ipmaCode, warningAreaCode)
    -- Update the text displays
    if locationText then
        locationText.text = string.format("Latitude: %.6f\nLongitude: %.6f", latitude, longitude)
    else
        print("Error: locationText element not found")
    end
    
    if districtText then
        districtText.text = "District: " .. district
    else
        print("Error: districtText element not found")
    end
    
    -- Determine safety based on IPMA warning data
    local isSafe, awarenessType = isDistrictSafe(warningAreaCode)
    
    if safetyText then
        if isSafe then
            safetyText.text = "⭐ This district is SAFE! ⭐"
            safetyText:setFillColor(0, 0.7, 0)  -- Green for safe
        else
            safetyText.text = "⚠️ This district is UNSAFE! ⚠️"
            safetyText:setFillColor(0.8, 0, 0)  -- Red for unsafe
        end
    else
        print("Error: safetyText element not found")
    end
    
    if awarenessText then
        awarenessText.text = "Warning: " .. awarenessType
    else
        print("Error: awarenessText element not found")
    end
    
    -- Print safety message
    if isSafe then
        print("Good news! You are in a SAFE district: " .. district)
    else
        print("Warning! You are in an UNSAFE district: " .. district)
    end

    --UpdateIndicator
    updateSafetyIndicator(isSafe)
end

function updateWarningIndicator(warningLevel)
    if not warningIndicator then
        print("Error: warningIndicator UI element not found.")
        return
    end

    -- Determine color based on warning level
    local color = {0, 1, 0} -- Default to green (RGB)
    if warningLevel == "red" or warningLevel == "orange" then
        color = {1, 0, 0} -- Set to red
    end

    -- Apply the color update
    warningIndicator:setFillColor(unpack(color))

    -- Force UI refresh if necessary
    warningIndicator:invalidate() -- Use if Solar2D or framework supports it

    print("Updated warning indicator to:", warningLevel)
end


-- Function to refresh all safety data
local function refreshAllSafetyData()
    if statusText then
        statusText.text = "Refreshing all safety data..."
    end
    
    -- Fetch warning data from the IPMA API
    fetchIPMAWarnings(function(success)
        if success then
            if statusText then
                statusText.text = "All safety data updated"
            end
            
            -- If we have current coordinates, update the display
            if currentLatitude and currentLongitude then
                local district, ipmaCode, warningAreaCode = findDistrict(currentLatitude, currentLongitude)
                updateLocationDisplay(currentLatitude, currentLongitude, district, ipmaCode, warningAreaCode)
            end
        else
            if statusText then
                statusText.text = "Failed to update safety data"
            end
        end
    end)
end

-- Simulate location function update
local function simulateLocation()
    -- Predefined locations with coordinates
    local locations = {
        { name = "Lisbon", lat = 38.7223, long = -9.1393 },
        { name = "Porto", lat = 41.1579, long = -8.6291 },
        { name = "Faro", lat = 37.0193, long = -7.9304 },
        { name = "Braga", lat = 41.5454, long = -8.4265 },
        { name = "Coimbra", lat = 40.2033, long = -8.4103 }
    }
    
    -- Simple random number between 1 and 5
    local index = math.random(1, 5)
    
    -- Get the selected location
    local location = locations[index]
    
    -- Update status
    if statusText then
        statusText.text = "Simulating: " .. location.name
    end
    
    -- Update coordinates and get district info
    currentLatitude = location.lat
    currentLongitude = location.long
    local district, ipmaCode, warningAreaCode = findDistrict(currentLatitude, currentLongitude)
    
    -- Update the display with the location data
    updateLocationDisplay(currentLatitude, currentLongitude, district, ipmaCode, warningAreaCode)
    
    -- Return true to indicate success
    return true
end

-- Simplified alert function
local function showSimpleAlert(title, message)
    -- Use native alert
    native.showAlert(title, message, {"OK"})
end

-- Location event handler function update
local function locationHandler(event)
    -- Check for error (user may have turned off location services)
    if event.errorCode then
        if statusText then
            statusText.text = "Location error: " .. event.errorMessage
        end
        native.showAlert("GPS Location Error", event.errorMessage, {"OK"})
    else
        -- Update status text
        if statusText then
            statusText.text = "GPS Location Updated"
        end
        
        -- Update current coordinates
        currentLatitude = event.latitude
        currentLongitude = event.longitude
        
        -- Determine district and fetch safety data
        local district, ipmaCode, warningAreaCode = findDistrict(currentLatitude, currentLongitude)
        
        -- Update display with location data
        updateLocationDisplay(currentLatitude, currentLongitude, district, ipmaCode, warningAreaCode)
    end
end

-- Function to start GPS tracking
local function startGPSTracking()
    -- Check if platform supports location events
    if system.hasEventSource("location") then
        -- Update status
        if statusText then
            statusText.text = "Starting GPS tracking..."
        end
        
        -- Activate location listener
        Runtime:addEventListener("location", locationHandler)
        
        -- Success message
        if statusText then
            statusText.text = "GPS tracking active"
        end
    else
        -- Platform doesn't support location
        if statusText then
            statusText.text = "GPS not supported on this platform"
        end
        showSimpleAlert("Platform Limitation", "Location events are not supported on this platform.", {"OK"})
    end
end

-- Function to stop GPS tracking
local function stopGPSTracking()
    -- Remove the location listener
    Runtime:removeEventListener("location", locationHandler)
    
    -- Update status
    if statusText then
        statusText.text = "GPS tracking stopped"
    end
end

------------------------
-- Initialize the UI --
------------------------

-- Device metrics for responsive design
local deviceW = display.contentWidth
local deviceH = display.contentHeight
local centerX = display.contentCenterX
local centerY = display.contentCenterY

-- Get actual screen dimensions (not just content area)
local screenW = display.actualContentWidth
local screenH = display.actualContentHeight

-- Scale factor calculation - adjusted for better text scaling
local baseWidth = 360 -- Reference width
local baseHeight = 640 -- Reference height
local scaleX = deviceW / baseWidth
local scaleY = deviceH / baseHeight
local scale = math.min(scaleX, scaleY) * 1.2 -- Adjusted to 1.2x for better balance

-- Constants for Material Design - improved color palette for better contrast
local materialColors = {
    primary = { 0.13, 0.59, 0.95 },       -- Blue 500 - Main buttons
    primaryDark = { 0.11, 0.51, 0.89 },   -- Blue 700 - Button hover states
    accent = { 0.0, 0.6, 0.6 },           -- Teal 500 
    accentPressed = { 0.0, 0.5, 0.5 },    -- Pressed State (Teal 700)
    background = { 0.96, 0.96, 0.98 },    -- Slightly blueish background for app
    cardBackground = { 1, 1, 1 },         -- Pure white for cards
    textPrimary = { 0, 0, 0, 0.87 },      -- Black 87% - Primary text
    textSecondary = { 0, 0, 0, 0.6 },     -- Black 60% - Secondary text
    divider = { 0, 0, 0, 0.12 },          -- Black 12% - Dividers
    danger = { 0.91, 0.3, 0.24 },         -- Red 500 - Danger areas
    warning = { 1, 0.76, 0.03 },          -- Amber 500 - Warning (changed from yellow for better contrast)
    success = { 0.3, 0.69, 0.31 }         -- Green 500 - Safe areas
}

-- Responsive typography with minimum font sizes
local function getFontSize(baseSize)
    local size = math.floor(baseSize * scale)
    return math.max(size, baseSize) -- Never go smaller than base size
end

local typography = {
    h1 = getFontSize(24),
    h2 = getFontSize(20),
    body1 = getFontSize(16),
    body2 = getFontSize(14),
    caption = getFontSize(12)
}

-- Responsive spacing with minimum values
local function getSpacing(baseSpacing)
    local spacing = math.floor(baseSpacing * scale)
    return math.max(spacing, baseSpacing) -- Never go smaller than base spacing
end

local spacing = {
    xs = getSpacing(4),
    sm = getSpacing(8),
    md = getSpacing(16),
    lg = getSpacing(24),
    xl = getSpacing(32)
}

local cornerRadius = 8 * scale
local elevationShadow = 2
local cardElevation = 1

-- Calculate percentage of screen width
local function percentWidth(percent)
    return deviceW * (percent / 100)
end

-- Calculate percentage of screen height
local function percentHeight(percent)
    return deviceH * (percent / 100)
end

-- Function to expand display to fill entire screen
local function expandToFullScreen()
    local background = display.newRect(centerX, centerY, screenW, screenH)
    background:setFillColor(unpack(materialColors.background))
    
    -- Position it to cover the entire screen
    background.x = display.screenOriginX + screenW/2
    background.y = display.screenOriginY + screenH/2
    
    return background
end

-- Improved shadow effect for cards and buttons
local function createShadowEffect(object, elevation)
    local shadowAlpha = math.min(0.3, 0.08 * elevation) -- Increased alpha for better visibility
    local shadowBlur = 3 * elevation * scale -- Increased blur for softer shadows
    local shadowOffsetY = elevation * scale / 2
    
    -- Remove previous shadow if it exists
    if object.shadow then
        object.shadow:removeSelf()
        object.shadow = nil
    end
    
    object.shadow = display.newRoundedRect(object.x, object.y + shadowOffsetY, object.width + shadowBlur, object.height + shadowBlur, object.path and cornerRadius or 0)
    object.shadow:setFillColor(0, 0, 0, shadowAlpha)
    object.shadow:toBack()
    object.shadow.blur = shadowBlur
    
    object.parent:insert(object.shadow)
    return object.shadow
end

-- Material Design Card component with improved shadows
local function createCard(x, y, width, height)
    local cardGroup = display.newGroup()
    
    local card = display.newRoundedRect(x, y, width, height, cornerRadius)
    
    -- Add card to group first
    cardGroup:insert(card)
    
    -- Then add shadow (ensures proper layering)
    createShadowEffect(card, cardElevation)
    
    return cardGroup, card
end



-- Material Design Button with improved resolution and clean edges (no shadows)
local function createMaterialButton(options)
    local buttonGroup = display.newGroup()
    
    -- Use passed width or calculate based on screen percentage
    local width = options.width or percentWidth(40)
    -- Ensure minimum button height for touchability
    local height = options.height or math.max(48, math.floor(48 * scale))
    
    -- Button background with vector graphics for crisp edges
    local btn = display.newRoundedRect(options.x, options.y, width, height, cornerRadius)
    
    -- Enable vector rendering for crisp edges at all resolutions
    btn.anchorX = 0.5
    btn.anchorY = 0.5
    btn.isAntiAliased = true
    
    -- Default style (contained)
    if not options.style or options.style == "contained" then
        btn:setFillColor(unpack(options.color or materialColors.primary))
    elseif options.style == "outlined" then
        btn:setFillColor(1, 1, 1)
        -- Use precise stroke width (avoid decimal values for cleaner rendering)
        btn.strokeWidth = math.max(1, math.floor(scale))
        btn:setStrokeColor(unpack(options.color or materialColors.primary))
    elseif options.style == "text" then
        btn.alpha = 0
    end
    
    -- Calculate maximum text width to prevent overflow
    local maxTextWidth = width - spacing.md * 2
    
    -- Button text with improved typography
    local buttonText = options.label
    
    -- Create button text with crisp rendering
    local btnText = display.newText({
        text = buttonText,
        x = options.x,
        y = options.y,
        font = native.systemFontBold,
        fontSize = math.max(15, typography.body1 - 1),
        align = "center"
    })
    
    -- Ensure text doesn't overflow
    if btnText.width > maxTextWidth then
        -- Use integer scale factor for cleaner text rendering
        local ratio = maxTextWidth / btnText.width
        btnText.xScale = math.floor(ratio * 100) / 100
    end
    
    if not options.style or options.style == "contained" then
        btnText:setFillColor(1)
    else
        btnText:setFillColor(unpack(options.color or materialColors.primary))
    end
    
    -- Clean visual feedback without shadows - just color change
    btn:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(btn)
            btn.isFocused = true
            
            -- Visual feedback - color change only
            if not options.style or options.style == "contained" then
                btn:setFillColor(unpack(options.colorOver or materialColors.primaryDark))
            else
                btn.alpha = 0.7
            end
            
            return true
        elseif btn.isFocused then
            if event.phase == "ended" then
                -- Reset visual state
                if not options.style or options.style == "contained" then
                    btn:setFillColor(unpack(options.color or materialColors.primary))
                else
                    btn.alpha = options.style == "text" and 0 or 1
                end
                
                display.getCurrentStage():setFocus(nil)
                btn.isFocused = false
                
                -- Call the provided function
                if event.x >= btn.contentBounds.xMin and
                   event.x <= btn.contentBounds.xMax and
                   event.y >= btn.contentBounds.yMin and
                   event.y <= btn.contentBounds.yMax then
                    if options.onRelease then
                        options.onRelease()
                    end
                end
            end
            
            return true
        end
        
        return false
    end)
    
    buttonGroup:insert(btn)
    buttonGroup:insert(btnText)
    
    return buttonGroup
end

-- Material Design Switch with improved visual feedback
local function createSwitch(options)
    local switchGroup = display.newGroup()
    
    -- Ensure switch is large enough to be usable
    local trackWidth = math.max(36, 36 * scale)
    local trackHeight = math.max(14, 14 * scale)
    local thumbSize = math.max(20, 20 * scale)
    
    -- Track with rounded ends
    local track = display.newRoundedRect(options.x, options.y, trackWidth, trackHeight, trackHeight/2)
    track:setFillColor(unpack(materialColors.divider))
    
    -- Thumb with improved shadow
    local thumb = display.newCircle(options.x - trackWidth/4, options.y, thumbSize/2)
    thumb:setFillColor(0.9, 0.9, 0.9)
    createShadowEffect(thumb, 1)
    
    -- Label with larger text
    local label
    if options.label then
        label = display.newText({
            text = options.label,
            x = options.x - trackWidth/2 - 8 * scale,
            y = options.y,
            font = native.systemFont,
            fontSize = math.max(14, typography.body2),
            align = "right"
        })
        label.anchorX = 1
        label:setFillColor(unpack(materialColors.textPrimary))
    end
    
    -- State
    local isOn = options.initialState or false
    if isOn then
        thumb.x = options.x + trackWidth/4
        track:setFillColor(unpack(materialColors.primary))
        thumb:setFillColor(unpack(materialColors.primary))
    end
    
    -- Improved interaction with animation
    local function toggle()
        isOn = not isOn
        
        -- Add subtle bounce animation
        if isOn then
            transition.to(thumb, {
                time = 150,
                x = options.x + trackWidth/4,
                transition = easing.outQuad,
                onComplete = function()
                    transition.to(thumb, {time=70, xScale=1.1, yScale=1.1, transition=easing.outQuad, onComplete=function()
                        transition.to(thumb, {time=70, xScale=1, yScale=1})
                    end})
                end
            })
            track:setFillColor(unpack(materialColors.primary))
            thumb:setFillColor(unpack(materialColors.primary))
        else
            transition.to(thumb, {
                time = 150,
                x = options.x - trackWidth/4,
                transition = easing.outQuad
            })
            track:setFillColor(unpack(materialColors.divider))
            thumb:setFillColor(0.9, 0.9, 0.9)
        end
        
        if options.onToggle then
            options.onToggle(isOn)
        end
    end
    
    track:addEventListener("tap", toggle)
    thumb:addEventListener("tap", toggle)
    if label then
        label:addEventListener("tap", toggle)
    end
    
    switchGroup:insert(track)
    switchGroup:insert(thumb)
    if label then
        switchGroup:insert(label)
    end
    
    return switchGroup
end

-- Create a Material Chip with improved selection state
local function createChip(options)
    local chipGroup = display.newGroup()
    
    -- Ensure chip is large enough to be readable and touchable
    local chipHeight = math.max(32, 32 * scale)
    local padding = math.max(12, 12 * scale)
    
    -- Calculate width based on text with larger font
    local tempText = display.newText({
        text = options.label,
        font = native.systemFont,
        fontSize = math.max(14, typography.body2)
    })
    local chipWidth = tempText.width + padding * 2
    tempText:removeSelf()
    
    -- Chip background with improved visual style
    local chip = display.newRoundedRect(options.x, options.y, chipWidth, chipHeight, chipHeight/2)
    
    if options.selected then
        chip:setFillColor(unpack(materialColors.primary))
        -- Add subtle inner glow for selected state
        chip.stroke = { materialColors.primary[1]*1.2, materialColors.primary[2]*1.2, materialColors.primary[3]*1.2 }
        chip.strokeWidth = 1
    else
        chip:setFillColor(0.9, 0.9, 0.9)
    end
    
    -- Add subtle shadow
    createShadowEffect(chip, 1)
    
    -- Chip text with larger font
    local chipText = display.newText({
        text = options.label,
        x = options.x,
        y = options.y,
        font = native.systemFont,
        fontSize = math.max(14, typography.body2)
    })
    
    if options.selected then
        chipText:setFillColor(1)
    else
        chipText:setFillColor(unpack(materialColors.textPrimary))
    end
    
    -- Click handling with feedback
    chip:addEventListener("tap", function()
        -- Add subtle tap animation
        transition.to(chip, {time=100, xScale=0.95, yScale=0.95, onComplete=function()
            transition.to(chip, {time=100, xScale=1, yScale=1})
            if options.onTap then
                options.onTap()
            end
        end})
    end)
    
    chipGroup:insert(chip)
    chipGroup:insert(chipText)
    
    return chipGroup, chipWidth
end

-- Create background that fills the entire screen
local background = expandToFullScreen()

-- Create main content card - responsive positioning and sizing with improved shadow
local mainCardWidth = screenW -- Use full screen width instead of percentage
local mainCardHeight = screenH -- Use full screen height instead of percentage
local mainContentY = centerY -- Center vertically in the screen
local mainCard, mainCardBg = createCard(centerX, mainContentY, mainCardWidth, mainCardHeight)

-- Location info in card - larger text and improved positioning
locationText = display.newText({
    text = "Latitude: --\nLongitude: --",
    x = mainCardBg.x - mainCardBg.width/2 + spacing.lg,
    y = mainCardBg.y - mainCardBg.height/2 + spacing.lg,
    font = native.systemFont,
    fontSize = math.max(15, typography.body2), -- Ensure minimum readable size
    align = "left"
})
locationText.anchorX = 0
locationText:setFillColor(unpack(materialColors.textSecondary))

-- Create a safety indicator widget with improved visual style
local indicatorSize = math.max(32, 32 * scale)
-- Replace the safety indicator creation with a cleaner version
local indicatorSize = math.max(32, 32 * scale)
local safetyIndicator = display.newCircle(
    mainCardBg.x + mainCardBg.width/2 - spacing.lg, 
    locationText.y, 
    indicatorSize/2
)
safetyIndicator:setFillColor(0.5, 0.5, 0.5) -- Gray (unknown)
safetyIndicator.isAntiAliased = true -- Enable anti-aliasing for crisp circle

-- Add a thin border for definition without using shadows
safetyIndicator.strokeWidth = 1
safetyIndicator:setStrokeColor(0.4, 0.4, 0.4)

-- Add glow effect to the indicator
local function updateIndicatorGlow(indicator, color)
    -- Remove previous glow if exists
    if indicator.glow then
        indicator.glow:removeSelf()
        indicator.glow = nil
    end
    
    -- Create glow effect
    indicator.glow = display.newCircle(indicator.x, indicator.y, indicatorSize/1.6)
    indicator.glow:setFillColor(color[1], color[2], color[3], 0.3)
    indicator.parent:insert(indicator.glow)
    indicator.glow:toBack()
    
    -- Pulsing animation
    local function pulseGlow()
        transition.to(indicator.glow, {time=1500, alpha=0.1, xScale=1.3, yScale=1.3, onComplete=function()
            transition.to(indicator.glow, {time=1500, alpha=0.3, xScale=1, yScale=1, onComplete=pulseGlow})
        end})
    end
    
    pulseGlow()
end

-- District display with improved typography and visual hierarchy
districtText = display.newText({
    text = "District: --",
    x = mainCardBg.x,
    y = mainCardBg.y - mainCardBg.height/4 + spacing.md,
    font = native.systemFontBold,
    fontSize = math.max(22, typography.h1), -- Ensure minimum readable size
    align = "center"
})
districtText:setFillColor(unpack(materialColors.textPrimary))

-- Add a divider with improved visual style - slight gradient
local dividerWidth = mainCardBg.width - spacing.lg*2
local divider = display.newRect(mainCardBg.x, mainCardBg.y, dividerWidth, math.max(1, scale))

-- Create gradient for divider
local dividerPaint = {
    type = "gradient",
    color1 = { materialColors.divider[1], materialColors.divider[2], materialColors.divider[3], 0.1 },
    color2 = { materialColors.divider[1], materialColors.divider[2], materialColors.divider[3], materialColors.divider[4] },
    color3 = { materialColors.divider[1], materialColors.divider[2], materialColors.divider[3], 0.1 },
    direction = "horizontal"
}
divider.fill = dividerPaint

-- Safety status with improved typography and contrast
safetyText = display.newText({
    text = "Safety status unknown",
    x = mainCardBg.x,
    y = mainCardBg.y - spacing.md,
    font = native.systemFontBold,
    fontSize = math.max(18, typography.body1), -- Ensure minimum readable size
    align = "center"
})
safetyText:setFillColor(unpack(materialColors.textPrimary))

-- Awareness type with improved typography
awarenessText = display.newText({
    text = "Warning: --",
    x = mainCardBg.x,
    y = mainCardBg.y + spacing.lg*2,
    font = native.systemFont,
    fontSize = math.max(16, typography.body1), -- Ensure minimum readable size
    align = "center"
})
awarenessText:setFillColor(unpack(materialColors.textSecondary))

-- Add controls using Material styling - adjust positioning relative to the main card
local buttonsY = deviceH - spacing.xl * 3 

-- Calculate button positions based on screen width
local leftButtonX = centerX - percentWidth(22)
local rightButtonX = centerX + percentWidth(22)
local gpsTrackingActive = false

-- Add a status text element at the top of the app
statusText = display.newText({
    text = "Ready",
    x = centerX,
    y = spacing.xl,
    font = native.systemFont,
    fontSize = typography.body1,
    align = "center"
})
statusText:setFillColor(unpack(materialColors.textSecondary))

-- Update button creation calls with fixed parameters for GPS button
gpsButton = createMaterialButton({
    x = leftButtonX,
    y = buttonsY + 4*spacing.md,
    width = percentWidth(38),
    height = math.max(48, 48 * scale),
    label = "Start GPS",
    color = materialColors.primary,
    colorOver = materialColors.primaryDark,
    onRelease = function()
        if not gpsTrackingActive then
            gpsTrackingActive = true
            if startGPSTracking then
                startGPSTracking()
            else
                print("Warning: startGPSTracking function not defined")
            end
            gpsButton[2].text = "Stop GPS"
        else
            gpsTrackingActive = false
            if stopGPSTracking then
                stopGPSTracking()
            else
                print("Warning: stopGPSTracking function not defined")
            end
            gpsButton[2].text = "Start GPS"
        end
    end
})

-- Update button creation calls with fixed parameters for Simulate button
local simulateButton = createMaterialButton({
    x = rightButtonX,
    y = buttonsY + 4*spacing.md,
    width = percentWidth(38),
    height = math.max(48, 48 * scale),
    label = "Simulate",
    color = materialColors.accent,
    colorOver = materialColors.accentPressed,
    onRelease = function()
        if simulateLocation then
            simulateLocation()
        else
            print("Warning: simulateLocation function not defined")
        end
    end
})

-- Show map button with outline style - larger text and improved visual style
local showMapButton = createMaterialButton({
    x = centerX,
    y = buttonsY + 2.5 * spacing.xl + math.max(48, 48 * scale), -- Position below other buttons
    width = percentWidth(80),
    height = math.max(48, 48 * scale),
    label = "Show Location on Map",
    style = "outlined",
    onRelease = function()
        -- Check for variable definitions that should exist elsewhere
        if currentLatitude and currentLongitude then
            local mapURL = "https://maps.google.com/maps?q=Portugal+Safety+Mapper@" .. currentLatitude .. "," .. currentLongitude
            if system.openURL then
                if not system.openURL(mapURL) then
                    if native and native.showAlert then
                        native.showAlert("Alert", "No browser found to show location on map!", {"OK"})
                    else
                        print("Error: Cannot open map URL and native.showAlert is not available")
                    end
                end
            else
                print("Error: system.openURL is not available")
            end
        else
            if native and native.showAlert then
                native.showAlert("No Location", "Please get a location first using GPS or simulation.", {"OK"})
            else
                print("Error: No location available and native.showAlert is not available")
            end
        end
    end
})

-- Information text with improved positioning and styling
local infoText = display.newText({
    text = "Data source: IPMA API",
    x = centerX,
    y = deviceH + 5*spacing.md,
    font = native.systemFont,
    fontSize = math.max(12, typography.caption), -- Ensure minimum readable size
    align = "center"
})
infoText:setFillColor(unpack(materialColors.textSecondary))


-- Clean indicator state update without shadow effects
function updateSafetyIndicator(isSafe)
    if not safetyIndicator then
        print("Error: safetyIndicator not found")
        return
    end
    
    if isSafe == true then
        -- Safe state with clean transition
        transition.to(safetyIndicator, {
            time = 300,
            onComplete = function()
                safetyIndicator:setFillColor(unpack(materialColors.success))
                safetyIndicator:setStrokeColor(
                    materialColors.success[1] * 0.8, 
                    materialColors.success[2] * 0.8, 
                    materialColors.success[3] * 0.8
                )
            end
        })        
    elseif isSafe == false then
        -- Unsafe state with clean transition
        transition.to(safetyIndicator, {
            time = 300,
            onComplete = function()
                safetyIndicator:setFillColor(unpack(materialColors.danger))
                safetyIndicator:setStrokeColor(
                    materialColors.danger[1] * 0.8, 
                    materialColors.danger[2] * 0.8, 
                    materialColors.danger[3] * 0.8
                )
            end
        })
    else
        -- Unknown state with clean transition
        transition.to(safetyIndicator, {
            time = 300, 
            onComplete = function()
                safetyIndicator:setFillColor(0.5, 0.5, 0.5)
                safetyIndicator:setStrokeColor(0.4, 0.4, 0.4)
            end
        })
    end
end


-- Add orientation change listener to handle screen rotation with improved reliability
local function onOrientationChange(event)
    -- Update device metrics
    deviceW = display.contentWidth
    deviceH = display.contentHeight
    centerX = display.contentCenterX
    centerY = display.contentCenterY
    screenW = display.actualContentWidth
    screenH = display.actualContentHeight
    
    -- Recalculate scale factors
    scaleX = deviceW / baseWidth
    scaleY = deviceH / baseHeight
    scale = math.min(scaleX, scaleY) * 1.2
    
    -- Update background to cover full screen
    background.width = screenW
    background.height = screenH
    background.x = display.screenOriginX + screenW/2
    background.y = display.screenOriginY + screenH/2
    
    -- Update toolbar group
    if toolbarGroup then
        -- First recalculate toolbar height
        local toolbarHeight = math.max(percentHeight(8), 56)
        local toolbarY = display.screenOriginY + toolbarHeight/2
        
        -- Update toolbar elements within the group
        for i = 1, toolbarGroup.numChildren do
            local child = toolbarGroup[i]
            child.width = screenW
            child.x = centerX
            child.y = toolbarY
        end
        
        -- Special handling for toolbar title
        if toolbarTitle then
            toolbarTitle.x = spacing.lg
            toolbarTitle.y = toolbarY
        end
    end
end

if mainCardBg then
    mainCardBg.width = screenW
    mainCardBg.height = screenH
    mainCardBg.x = centerX
    mainCardBg.y = centerY
    
    -- Update card shadow
    createShadowEffect(mainCardBg, cardElevation)
end
-- Update location text
if locationText then
    locationText.x = mainCardBg.x - mainCardBg.width/2 + spacing.md
end

-- Call the initialization function when the app starts
initializeApp()