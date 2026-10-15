local Utils = {}

function Utils:subtract(newData, oldData)
    local function subtractSubtable(newSub, oldSub)
        if not newSub or not oldSub then return end
        for k, oldVal in pairs(oldSub) do
            if newSub[k] == oldVal then
                newSub[k] = nil
            end
        end
    end

    subtractSubtable(newData.varbit, oldData.varbit)
    subtractSubtable(newData.varp, oldData.varp)
    subtractSubtable(newData.level, oldData.level)
end

function Utils:merge(oldData, delta)
    local function mergeSubtable(oldSub, deltaSub)
        if not deltaSub then return end
        for k, newVal in pairs(deltaSub) do
            oldSub[k] = newVal
        end
    end

    mergeSubtable(oldData.varbit, delta.varbit)
    mergeSubtable(oldData.varp, delta.varp)
    mergeSubtable(oldData.level, delta.level)
end

function Utils:newPlayerData()
    return { varbit = {}, varp = {}, level = {} }
end

function Utils:playerDataIsEmpty(data)
    return next(data.varbit) == nil and next(data.varp) == nil and next(data.level) == nil
end

return Utils
