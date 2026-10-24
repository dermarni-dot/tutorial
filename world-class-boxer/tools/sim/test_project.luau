-- test_project: default.project.json maps every server module the scripts require (the simulator loads files
-- straight from src/, so a module missing from the project file passes every other test and then does not exist
-- in the built place: Main hangs on its require and the world never builds)
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local root = "../.."
local pass, fail = 0, 0
local function check(name, ok, info)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (info and (": " .. tostring(info)) or ""))
	end
end

local project = serde.decode("json", fs.readFile(root .. "/default.project.json"))
local sss = project.tree.ServerScriptService
local mods = sss and sss.BoxerModules or {}
local mapped = {}
for name, node in pairs(mods) do
	if type(node) == "table" and node["$path"] then
		mapped[name] = node["$path"]
	end
end

-- every module file in src/server is mapped under BoxerModules, by its own name
for _, f in ipairs(fs.readDir(root .. "/src/server")) do
	if f:match("%.lua$") and not f:match("%.server%.lua$") then
		local name = f:gsub("%.lua$", "")
		check("src/server/" .. f .. " is in default.project.json", mapped[name] == "src/server/" .. f, mapped[name])
	end
end

-- every mapped path exists
for name, path in pairs(mapped) do
	check("BoxerModules." .. name .. " -> " .. path .. " exists", fs.isFile(root .. "/" .. path))
end

-- every server-side require by name resolves to a mapped module
for _, f in ipairs(fs.readDir(root .. "/src/server")) do
	if f:match("%.lua$") then
		local src = fs.readFile(root .. "/src/server/" .. f)
		for m in src:gmatch("require%(%s*script%.Parent%.(%w+)") do
			check(f .. " requires " .. m, mapped[m] ~= nil)
		end
		for m in src:gmatch("require%(%s*Modules%.(%w+)") do
			check(f .. " requires " .. m, mapped[m] ~= nil)
		end
		for m in src:gmatch("Modules:WaitForChild%(\"(%w+)\"%)") do
			check(f .. " waits for " .. m, mapped[m] ~= nil)
		end
	end
end

-- the client and shared trees are whole folders (new files there are picked up on their own)
local sps = project.tree.StarterPlayer and project.tree.StarterPlayer.StarterPlayerScripts
check("client modules are a folder mapping", sps and sps.BoxerClient and sps.BoxerClient["$path"] == "src/client/modules")
check("shared is a folder mapping", project.tree.ReplicatedStorage.Shared["$path"] == "src/shared")

print(string.format("test_project: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_project failed")
end
