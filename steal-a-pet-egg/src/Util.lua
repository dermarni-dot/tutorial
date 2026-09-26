-- Util (ModuleScript) — ReplicatedStorage.Shared.Util

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Util.FormatNumber(n: number): string
	if n < 100 and n ~= math.floor(n) then
		return string.format("%.1f", math.floor(n * 10) / 10)
	end
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local index = 1
	local value = n
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	if string.find(text, "%.") then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	return text .. SUFFIXES[index]
end

function Util.Money(n: number): string
	return "$" .. Util.FormatNumber(n)
end

function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	if minutes > 0 then
		return string.format("%d:%02d", minutes, rest)
	end
	return rest .. "s"
end

-- Picks one item from a list using getWeight(item) as its weight.
function Util.WeightedPick(items, getWeight, rng)
	local total = 0
	for _, item in ipairs(items) do
		total += getWeight(item)
	end
	if total <= 0 then
		return nil
	end
	local roll = (if rng then rng:NextNumber() else math.random()) * total
	for _, item in ipairs(items) do
		roll -= getWeight(item)
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

return Util
