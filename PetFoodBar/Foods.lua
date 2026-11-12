--[[
    Foods.lua - Pet Food Diet Database for Vanilla 1.12 & Turtle WoW
]]

PetFood_Diets = {
    ["fungus"] = {
        4607, 8948, 4604, 4608, 4605, 3448, 4606,
    },
    ["fish"] = {
        13889, 19996, 13933, 13888, 13935, 13546, 6290, 4593, 5503, 16971,
        2682, 13927, 2675, 13930, 5476, 4655, 6038, 13928, 13929, 13893,
        4592, 8364, 13932, 5095, 6291, 6308, 13754, 6317, 6289, 8365,
        6361, 13758, 6362, 6303, 8959, 4603, 13756, 13760, 4594, 787,
        5468, 15924, 12216, 8957, 6887, 5504, 12206, 13755, 7974,
    },
    ["meat"] = {
        21235, 19995, 4457, 3173, 2888, 3730, 3726, 3220, 2677, 3404,
        12213, 2679, 769, 2673, 2684, 1081, 12224, 5479, 3662, 3664,
        3665, 2687, 724, 12215, 6888, 5527, 3727, 13851, 12212, 12214,
        5472, 729, 5480, 12209, 3663, 12218, 1015, 12223, 730, 1082,
        5474, 12210, 731, 1017, 3729, 2680, 17222, 5477, 2672, 2685,
        3728, 3667, 12208, 18045, 5470, 12202, 117, 3712, 12205, 3771,
    },
    ["bread"] = {
        1113, 5349, 1487, 1114, 8075, 8076, 22895, 19696, 21254, 2683,
        4541, 17197, 3666, 8950, 4542, 4544, 4601, 4540, 16169,
    },
    ["cheese"] = {
        8932, 414, 2070, 422, 3927, 1707,
    },
    ["fruit"] = {
        19994, 8953, 4539, 16168, 4602, 4536, 4538, 4537, 11950,
    },
}

-- Fast inverted lookup table: PetFood_Lookup[itemID] = { "meat" = true, ... }
PetFood_Lookup = {}

for diet, items in pairs(PetFood_Diets) do
    for _, itemID in ipairs(items) do
        if not PetFood_Lookup[itemID] then
            PetFood_Lookup[itemID] = {}
        end
        PetFood_Lookup[itemID][diet] = true
    end
end

-- Check if an item matches one of the pet's diets
function PetFood_MatchesPet(itemID, allowedDiets)
    if not itemID or not allowedDiets then return false end
    local itemDiets = PetFood_Lookup[itemID]
    if itemDiets then
        for dietName, _ in pairs(allowedDiets) do
            if itemDiets[dietName] then
                return true
            end
        end
    end
    return false
end
