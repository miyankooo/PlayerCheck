local addonName, ns = ...

local TITLE = "Armory Links"
local COPIED_FORMAT = "%s link copied."
local CLOSE_LABEL = "Close After Copying"
local CLOSE_HELP = "Closes this window when you copy a link. Turn it off to copy several links in a row."

-- macOS copies with Cmd only, so there Ctrl must not count as a copy. The key names are Blizzard's own,
-- localized as the keyboard labels them, such as STRG on a German client.
local IS_MAC = IsMacClient()
local isCopyModifierDown = IS_MAC and IsMetaKeyDown or IsControlKeyDown
local COPY_HINT = ("Press %s-C to copy the selected link. Tab selects the next one."):format(IS_MAC and CMD_KEY_TEXT or CTRL_KEY_TEXT)

-- The widest dialog, so as much of each link as possible shows.
local WIDTH = 480

-- Spacing roles: tight from text to its control, gap from the name to the hint, the padding step between two
-- links so each label reads with its own box, and a section break around the list of links.
local TIGHT = 4
local GAP = 8
local LINK_GAP = 16

-- A site label is one 12 px heading line; the copied mark is an inline icon.
local LABEL_HEIGHT = 12
local ICON_SIZE = 16

-- InputBoxTemplate's art height and its left cap outside the box (InputBoxTemplates.xml:47-49).
local EDIT_BOX_HEIGHT = 20
local EDIT_BOX_CAP = 5

-- CheckboxWithLabelTemplate at the 24 px row size.
local CHECKBOX_SIZE = 24

-- Long enough for the client to finish the copy before the edit box goes away.
local CLOSE_DELAY = 0.2

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
local function CreateText(parent, fontObject, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(fontObject or GameFontHighlight)
    text:SetJustifyH("LEFT")
    return text
end

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
local function AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Rounds a length derived from text up to the 4 px grid.
local function Snap(length)
    return math.ceil(length / 4) * 4
end

-- InputBoxTemplate draws its left cap 5 px outside the box (InputBoxTemplates.xml:49), so the caller indents the
-- box by 5 to line the art up with the column.
local function CreateEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    return box
end

-- CheckboxWithLabelTemplate: the minimal art Blizzard's Settings use, at the 24 px AddonList gives it
-- (Blizzard_AddOnList/AddonList.xml:73-74). The label joins the hit rect, so a click on it toggles the box.
local function CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "CheckboxWithLabelTemplate")
    checkbox:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
    return checkbox
end

-- Restores a saved position, or centres the frame.
local function RestorePosition(frame, position)
    frame:ClearAllPoints()
    if position and position.point then
        frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Windows and dialogs: toplevel, clamped, dragged with the left button, closed by Escape through UISpecialFrames,
-- never UIPanelWindows, so they never drive Blizzard's panel layout.
local function MakeMovable(frame, name, strata, position)
    frame:SetFrameStrata(strata)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if position then
            local point, _, relPoint, x, y = self:GetPoint(1)
            position.point, position.relPoint, position.x, position.y = point, relPoint, x, y
        end
    end)
    RestorePosition(frame, position)
    frame:Hide()
    tinsert(UISpecialFrames, name)
end

-- A dialog in Blizzard's dialog chrome: DialogBorderTemplate, DialogHeaderTemplate with the title and
-- UIPanelCloseButton 2 px in from the corner (Blizzard_Channels/Mainline/CreateChannelPopup.xml:72). Width is a
-- multiple of 8 from 400 to 480. Add content top to bottom with AddText and AddField, then call Fit.
-- AddButton is left out: this dialog has no buttons.
local DIALOG_SIDE, DIALOG_TOP, SECTION_GAP = 24, 40, 24
local function CreateDialog(name, title, width, parent, position)
    local dialog = CreateFrame("Frame", name, parent or UIParent)
    dialog:SetSize(width, DIALOG_TOP + DIALOG_SIDE)
    dialog.contentWidth = width - 2 * DIALOG_SIDE
    dialog.contentHeight = 0
    dialog.buttons = {}
    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
    dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate")
    dialog.Header:Setup(title)
    -- UIPanelCloseButton_OnClick goes through HideUIPanel, which refuses insecure callers in combat.
    dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.CloseButton:SetPoint("TOPRIGHT", -2, -2)
    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)

    -- Places a widget the caller sized in the content column below everything added so far; indent covers native
    -- art, 5 for an edit box. The gap defaults to 8; AddText passes a section break.
    function dialog:AddField(region, height, gap, indent)
        if self.hasContent then self.contentHeight = self.contentHeight + (gap or 8) end
        self.hasContent = true
        region:SetPoint("TOPLEFT", self, "TOPLEFT", DIALOG_SIDE + (indent or 0), -(DIALOG_TOP + self.contentHeight))
        self.contentHeight = self.contentHeight + height
    end

    -- Wrapped text across the column, never less than one line, so text filled in later keeps its line.
    function dialog:AddText(fontObject, text, gap)
        local line = CreateText(self, fontObject)
        line:SetWidth(self.contentWidth)
        line:SetWordWrap(true)
        line:SetText(text or "")
        local _, lineHeight = fontObject:GetFont()
        local height = math.ceil(math.max(line:GetStringHeight(), lineHeight))
        line:SetHeight(height)
        self:AddField(line, height, gap or SECTION_GAP)
        return line
    end

    -- 40 top, the content, a section break and the button row if there are buttons, 24 bottom, on the grid.
    function dialog:Fit()
        local height = DIALOG_TOP + self.contentHeight + DIALOG_SIDE
        if #self.buttons > 0 then height = height + SECTION_GAP + 24 end
        self:SetHeight(Snap(height))
    end

    MakeMovable(dialog, name, "DIALOG", position)
    return dialog
end

local dialog

-- Off only when the player unticked Close After Copying.
local function closesOnCopy()
    return PlayerArmoryLinkDB.closeOnCopy ~= false
end

-- After the copy: the row gets its mark, the copy is confirmed in green like Blizzard's own short notices, and
-- the dialog closes unless the player keeps it open for more links.
local function confirmCopy(frame, row)
    row.copied:Show()
    UIErrorsFrame:AddMessage(COPIED_FORMAT:format(row.site.name), GREEN_FONT_COLOR:GetRGBA())
    if closesOnCopy() then
        frame:Hide()
    end
end

-- One site: its name as a gold label, a check mark once copied, and the link in a box that always holds it
-- whole. InputBoxTemplate selects the text on focus and moves to nextEditBox on Tab (InputBoxTemplates.lua:1-15).
local function createRow(frame, site)
    local row = { site = site }

    row.label = CreateText(frame, GameFontNormal)
    row.label:SetText(site.name)

    row.copied = frame:CreateTexture(nil, "ARTWORK")
    row.copied:SetAtlas("common-icon-checkmark")
    row.copied:SetSize(ICON_SIZE, ICON_SIZE)
    row.copied:SetPoint("LEFT", row.label, "RIGHT", TIGHT, 0)

    local box = CreateEditBox(frame, frame.contentWidth - EDIT_BOX_CAP)
    row.box = box
    box:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    -- A click places the cursor and drops the selection, so the whole link is selected again.
    box:SetScript("OnMouseUp", EditBox_HighlightText)

    -- InputBoxTemplate sets no OnEnter (InputBoxTemplates.xml:3-10), so the recipe's SetScript is safe here.
    AttachTooltip(box, function(tooltip)
        GameTooltip_SetTitle(tooltip, site.name)
        GameTooltip_AddNormalLine(tooltip, site.help)
    end)

    -- Reverts any edit, so the link stays intact and selected.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= row.url then
            self:SetText(row.url)
            self:HighlightText()
        end
    end)

    -- CopyToClipboard is restricted, so the copy is the player's own keypress. The link is selected again
    -- before the client copies, so the copy is never partial.
    box:SetScript("OnKeyDown", function(self, key)
        if key ~= "C" or not isCopyModifierDown() then
            return
        end
        self:HighlightText()
        C_Timer.After(CLOSE_DELAY, function()
            confirmCopy(frame, row)
        end)
    end)
    return row
end

-- Whose links as the subject line, how to copy them in white body text, one row per site, then the option.
-- Above the centre so the character stays visible.
local function createDialog()
    local frame = CreateDialog(addonName .. "Dialog", TITLE, WIDTH, nil, { point = "CENTER", y = 140 })
    frame.name = frame:AddText(GameFontNormalLarge, "")
    frame:AddText(GameFontHighlight, COPY_HINT, GAP)
    frame.listTop = frame.contentHeight

    frame.rows = {}
    for index, site in ipairs(ns.SITES) do
        frame.rows[index] = createRow(frame, site)
    end

    frame.closeOnCopy = CreateCheckbox(frame, CLOSE_LABEL)
    frame.closeOnCopy:SetScript("OnClick", function(self)
        PlayerArmoryLinkDB.closeOnCopy = self:GetChecked()
    end)
    -- CheckboxWithLabelTemplate sets no OnEnter (CheckButtonTemplates.xml:78-89).
    AttachTooltip(frame.closeOnCopy, function(tooltip)
        GameTooltip_SetTitle(tooltip, CLOSE_LABEL)
        GameTooltip_AddNormalLine(tooltip, CLOSE_HELP)
    end)
    return frame
end

-- Lays out the rows that have a link, in site order, chains their boxes for Tab in a loop, puts the option
-- under them and fits the height. Returns the first box.
local function layOut(frame)
    frame.contentHeight = frame.listTop
    local first, previous
    for _, row in ipairs(frame.rows) do
        local shown = row.url ~= nil
        row.label:SetShown(shown)
        row.box:SetShown(shown)
        row.copied:Hide()
        if shown then
            row.box:SetText(row.url)
            row.box:SetCursorPosition(0)
            frame:AddField(row.label, LABEL_HEIGHT, first and LINK_GAP or SECTION_GAP)
            frame:AddField(row.box, EDIT_BOX_HEIGHT, TIGHT, EDIT_BOX_CAP)
            if previous then
                previous.nextEditBox = row.box
                row.box.previousEditBox = previous
            end
            first = first or row.box
            previous = row.box
        end
    end
    previous.nextEditBox = first
    first.previousEditBox = previous
    frame:AddField(frame.closeOnCopy, CHECKBOX_SIZE, SECTION_GAP)
    frame:Fit()
    return first
end

-- links: { site = site, url = url } in ns.SITES order, at least one.
function ns.ShowCopyDialog(displayName, links)
    dialog = dialog or createDialog()
    for _, row in ipairs(dialog.rows) do
        row.url = nil
        for _, link in ipairs(links) do
            if link.site == row.site then
                row.url = link.url
            end
        end
    end
    dialog.name:SetText(displayName)
    dialog.closeOnCopy:SetChecked(closesOnCopy())
    local first = layOut(dialog)
    dialog:Show()
    first:SetFocus()
    first:HighlightText()
end
