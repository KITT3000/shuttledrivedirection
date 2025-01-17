---
-- ShuttleDriveDirection
--
-- Toggles the drive direction.
--
-- Copyright (c) Wopster, 2019

ShuttleDriveDirection = {}
ShuttleDriveDirection.MOD_DIR = g_shuttleDriveDirectionModDirectory
ShuttleDriveDirection.MOD_NAME = g_shuttleDriveDirectionModName

ShuttleDriveDirection.DIR_FORWARDS = 1
ShuttleDriveDirection.DIR_NEUTRAL = 0
ShuttleDriveDirection.DIR_BACKWARDS = -1
ShuttleDriveDirection.BLINK_INTERVAL = 500
ShuttleDriveDirection.COLOR_NEUTRAL = { 0.0781, 0.2233, 0.0478, 0.75 }
ShuttleDriveDirection.COLOR_ACTIVE = { 0.0953, 1, 0.0685, 0.75 }

function ShuttleDriveDirection.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
end

function ShuttleDriveDirection.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getShuttleDriveDirection", ShuttleDriveDirection.getShuttleDriveDirection)
    SpecializationUtil.registerFunction(vehicleType, "setOnNeutral", ShuttleDriveDirection.setOnNeutral)
    SpecializationUtil.registerFunction(vehicleType, "isOnNeutral", ShuttleDriveDirection.isOnNeutral)
    SpecializationUtil.registerFunction(vehicleType, "toggleShuttleDriveDirection", ShuttleDriveDirection.toggleShuttleDriveDirection)
    SpecializationUtil.registerFunction(vehicleType, "setIsHoldingBrake", ShuttleDriveDirection.setIsHoldingBrake)
end

function ShuttleDriveDirection.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", ShuttleDriveDirection)
    SpecializationUtil.registerEventListener(vehicleType, "onStopMotor", ShuttleDriveDirection)
end

function ShuttleDriveDirection:onLoad(savegame)
    self.spec_shuttleDriveDirection = self[("spec_%s.shuttleDriveDirection"):format(ShuttleDriveDirection.MOD_NAME)]
    local spec = self.spec_shuttleDriveDirection

    spec.shuttleDirection = 0
    spec.shuttleDirectionSent = 0
    spec.isHoldingBrake = false
    spec.isHoldingBrakeSent = false
    spec.blinkTime = 0
    spec.doBlink = false

    local speedMeter = g_currentMission.inGameMenu.hud.speedMeter
    local baseX, baseY = speedMeter.gaugeBackgroundElement:getPosition()
    baseX = baseX + speedMeter.gaugeBackgroundElement:getWidth() * 0.5
    baseY = baseY + speedMeter.speedTextOffsetY

    local imagePath = Utils.getFilename("direction_arrow.png", ShuttleDriveDirection.MOD_DIR)
    spec.overlayForwards = ShuttleDriveDirection.createIcon(imagePath, speedMeter, baseX, baseY, { 10, -10.5 }, { 25, 25 }, false)
    spec.overlayBackwards = ShuttleDriveDirection.createIcon(imagePath, speedMeter, baseX, baseY, { 10, 14.5 }, { 25, 25 }, true)

    spec.dirtyFlag = self:getNextDirtyFlag()
end

function ShuttleDriveDirection.createIcon(imagePath, parent, baseX, baseY, position, size, isRotated)
    local posX, posY = parent:scalePixelToScreenVector(position)
    local width, height = parent:scalePixelToScreenVector(size)

    baseX = baseX - width * 0.5 -- center

    local iconOverlay = Overlay:new(imagePath, baseX - width - posX, baseY - posY, width, height)
    local element = HUDElement:new(iconOverlay)

    if isRotated then
        iconOverlay:setRotation(math.rad(180), width * 0.5, height * 0.5)
    end

    parent:addChild(element)
    element:setVisible(false)

    return element
end

function ShuttleDriveDirection:onDelete()
    local spec = self.spec_shuttleDriveDirection
    spec.overlayForwards:delete()
    spec.overlayBackwards:delete()
end

function ShuttleDriveDirection:onReadUpdateStream(streamId, timestamp, connection)
    local spec = self.spec_shuttleDriveDirection

    if streamReadBool(streamId) then
        spec.shuttleDirection = streamReadUIntN(streamId, 10) / 1023 * 2 - 1
        if math.abs(spec.shuttleDirection) < 0.00099 then
            spec.shuttleDirection = 0 -- set to 0 to avoid noise caused by compression
        end

        spec.isHoldingBrake = streamReadBool(streamId)
    end
end

function ShuttleDriveDirection:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self.spec_shuttleDriveDirection
    if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
        local shuttleDirection = (spec.shuttleDirection + 1) / 2 * 1023
        streamWriteUIntN(streamId, shuttleDirection, 10)
        streamWriteBool(streamId, spec.isHoldingBrake)
    end
end

function ShuttleDriveDirection:onUpdate(dt)
    if self.isClient then
        local spec = self.spec_shuttleDriveDirection

        if self:getIsActive() and self.getIsEntered ~= nil and self:getIsEntered() then
            if self:isOnNeutral() then
                spec.blinkTime = spec.blinkTime + dt
                if spec.blinkTime > ShuttleDriveDirection.BLINK_INTERVAL then
                    spec.doBlink = not spec.doBlink
                    spec.blinkTime = 0
                end
            end
        end

        if self.setBrakeLightsVisibility ~= nil then
            self:setBrakeLightsVisibility(spec.isHoldingBrake)
        end
    end
end

function ShuttleDriveDirection:onDraw()
    if self.isClient and ShuttleDriveDirection.canRenderOnCurrentVehicle(self) then
        if self:getIsActive() and self.getIsEntered ~= nil and self:getIsEntered() then
            local spec = self.spec_shuttleDriveDirection
            local forwardsColor = ShuttleDriveDirection.COLOR_NEUTRAL
            local backwardsColor = ShuttleDriveDirection.COLOR_NEUTRAL

            if spec.shuttleDirection == ShuttleDriveDirection.DIR_FORWARDS then
                forwardsColor = ShuttleDriveDirection.COLOR_ACTIVE
            elseif spec.shuttleDirection == ShuttleDriveDirection.DIR_BACKWARDS then
                backwardsColor = ShuttleDriveDirection.COLOR_ACTIVE
            elseif spec.shuttleDirection == ShuttleDriveDirection.DIR_NEUTRAL and spec.doBlink then
                forwardsColor = ShuttleDriveDirection.COLOR_ACTIVE
                backwardsColor = ShuttleDriveDirection.COLOR_ACTIVE
            end

            spec.overlayForwards:setColor(unpack(forwardsColor))
            spec.overlayBackwards:setColor(unpack(backwardsColor))
        end
    end
end

function ShuttleDriveDirection:onStopMotor()
    self:setOnNeutral()
end

function ShuttleDriveDirection:onEnterVehicle()
    if ShuttleDriveDirection.canRenderOnCurrentVehicle(self) then
        local spec = self.spec_shuttleDriveDirection
        spec.overlayForwards:setVisible(true)
        spec.overlayBackwards:setVisible(true)
    end
end

function ShuttleDriveDirection:onLeaveVehicle()
    if ShuttleDriveDirection.canRenderOnCurrentVehicle(self) then
        local spec = self.spec_shuttleDriveDirection
        spec.overlayForwards:setVisible(false)
        spec.overlayBackwards:setVisible(false)
    end
    self:setOnNeutral()
end

function ShuttleDriveDirection.canRenderOnCurrentVehicle(vehicle)
    return g_currentMission.controlledVehicle == vehicle
end

function ShuttleDriveDirection:getShuttleDriveDirection()
    return self.spec_shuttleDriveDirection.shuttleDirection
end

function ShuttleDriveDirection:setOnNeutral()
    self.spec_shuttleDriveDirection.shuttleDirection = ShuttleDriveDirection.DIR_NEUTRAL
end
function ShuttleDriveDirection:isOnNeutral()
    return self.spec_shuttleDriveDirection.shuttleDirection == ShuttleDriveDirection.DIR_NEUTRAL
end

function ShuttleDriveDirection:toggleShuttleDriveDirection()
    local spec = self.spec_shuttleDriveDirection
    if self:getShuttleDriveDirection() == ShuttleDriveDirection.DIR_NEUTRAL then
        self.spec_shuttleDriveDirection.shuttleDirection = ShuttleDriveDirection.DIR_BACKWARDS
    end

    spec.shuttleDirection = -spec.shuttleDirection

    if spec.shuttleDirection ~= spec.shuttleDirectionSent then
        spec.shuttleDirectionSent = spec.shuttleDirection
        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

function ShuttleDriveDirection:setIsHoldingBrake(isHoldingBrake)
    local spec = self.spec_shuttleDriveDirection

    spec.isHoldingBrake = isHoldingBrake

    if spec.isHoldingBrake ~= spec.isHoldingBrakeSent then
        spec.isHoldingBrakeSent = spec.isHoldingBrake
        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

function ShuttleDriveDirection:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_shuttleDriveDirection
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.TOGGLE_DRIVE_DIRECTION, self, ShuttleDriveDirection.toggleShuttleDriveDirection, false, true, false, true, nil)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
            g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_toggle_drive_direction"))
        end
    end
end
