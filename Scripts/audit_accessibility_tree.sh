#!/usr/bin/env bash
set -euo pipefail

PROCESS_NAME="${1:-Aviv}"
MAX_DEPTH="${2:-7}"

if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
    echo "maximum depth must be a non-negative integer" >&2
    exit 2
fi

osascript - "$PROCESS_NAME" "$MAX_DEPTH" <<'APPLESCRIPT'
on run arguments
    set processName to item 1 of arguments
    set maximumDepth to (item 2 of arguments) as integer

    tell application "System Events"
        if not (exists process processName) then
            error "Accessibility audit could not find a running process named " & processName
        end if
        tell process processName
            if (count of windows) is 0 then
                error "Accessibility audit found " & processName & " but it has no windows"
            end if
            set auditOutput to "depth\trole\tidentifier\ttitle\tdescription\thelp\tvalue\tenabled\tselected\tfocused"
            repeat with windowElement in windows
                set auditOutput to auditOutput & linefeed & my auditElement(windowElement, 0, maximumDepth)
            end repeat
        end tell
    end tell
    return auditOutput
end run

on auditElement(elementReference, depth, maximumDepth)
    set fields to {depth as text}
    repeat with attributeName in {"AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXHelp", "AXValue", "AXEnabled", "AXSelected", "AXFocused"}
        set end of fields to my safeAttribute(elementReference, attributeName as text)
    end repeat
    set outputText to my joinFields(fields)

    if depth < maximumDepth then
        tell application "System Events"
            try
                set childElements to UI elements of elementReference
            on error errorMessage number errorNumber
                error "Accessibility audit could not enumerate children at depth " & depth & ": " & errorMessage number errorNumber
            end try
        end tell
        repeat with childElement in childElements
            set outputText to outputText & linefeed & my auditElement(childElement, depth + 1, maximumDepth)
        end repeat
    end if
    return outputText
end auditElement

on safeAttribute(elementReference, attributeName)
    tell application "System Events"
        try
            set rawValue to value of attribute attributeName of elementReference
            if rawValue is missing value then return ""
            return my sanitizeAndClip(rawValue as text, 240)
        on error
            return ""
        end try
    end tell
end safeAttribute

on sanitizeAndClip(rawText, maximumLength)
    set cleanText to my replaceText(rawText, tab, " ")
    set cleanText to my replaceText(cleanText, return, " ")
    set cleanText to my replaceText(cleanText, linefeed, " ")
    if (count characters of cleanText) > maximumLength then
        return (text 1 thru (maximumLength - 1) of cleanText) & "…"
    end if
    return cleanText
end sanitizeAndClip

on replaceText(rawText, needle, replacement)
    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to needle
    set parts to text items of rawText
    set AppleScript's text item delimiters to replacement
    set joinedText to parts as text
    set AppleScript's text item delimiters to previousDelimiters
    return joinedText
end replaceText

on joinFields(fields)
    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to tab
    set joinedText to fields as text
    set AppleScript's text item delimiters to previousDelimiters
    return joinedText
end joinFields
APPLESCRIPT
