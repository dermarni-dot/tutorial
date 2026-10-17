-- tools/sim/test_hairassets_client.luau: the client loader (src/client/modules/HairAssets.lua) against a fake
-- AssetService: the piece records AnatomyClient swaps in, shared / private tinted images and their refcounts,
-- failure marking (the generated fallback), memory errors, cancellation, the transient retry. No real engine:
-- what Roblox does with the parts is not tested here.
--   lune run tools/sim/test_hairassets_client.luau
local Host = require("./host")
local Vector2 = require("@lune/roblox").Vector2

-- fake engine objects -------------------------------------------------------------------------------------
local live = { parts = 0, images = 0 }
local made = { parts = 0, images = 0 }
local failMesh, failTex, nilImage, yields = {}, {}, false, 0
local Content = {
	fromUri = function(u)
		return { uri = u }
	end,
	fromObject = function(o)
		return { object = o }
	end,
}
local function idOf(content)
	return tonumber(tostring(content.uri):match("(%d+)$"))
end
local function fakeImage(w, h, fill)
	live.images += 1
	made.images += 1
	local img = { Size = Vector2.new(w, h), destroyed = false }
	img.buf = buffer.create(w * h * 4)
	if fill then
		buffer.fill(img.buf, 0, fill)
	end
	function img.ReadPixelsBuffer(self)
		return buffer.fromstring(buffer.tostring(self.buf))
	end
	function img.WritePixelsBuffer(self, _pos, _size, b)
		self.buf = b
	end
	function img.Destroy(self)
		if not self.destroyed then
			self.destroyed = true
			live.images -= 1
		end
	end
	return img
end
local AssetService = {
	CreateMeshPartAsync = function(_, content, _opts)
		yields += 1
		local id = idOf(content)
		if failMesh[id] then
			error(failMesh[id], 0)
		end
		live.parts += 1
		made.parts += 1
		local p = { meshId = id, destroyed = false }
		function p.Destroy(self)
			if not self.destroyed then
				self.destroyed = true
				live.parts -= 1
			end
		end
		return p
	end,
	CreateEditableImageAsync = function(_, content)
		yields += 1
		local id = idOf(content)
		if failTex[id] then
			error(failTex[id], 0)
		end
		return fakeImage(id == 11 and 8 or 16, id == 11 and 8 or 16, 200)
	end,
	CreateEditableImage = function(_, opts)
		if nilImage then
			return nil
		end
		return fakeImage(opts.Size.X, opts.Size.Y)
	end,
}

local H = Host.new({ globals = { Content = Content } })
H.Service("AssetService")._props = AssetService
local HA = H.require("Client/HairAssets")
local Data = HA._data

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function look(g, hair)
	return (H.Look({ g = g, hair = hair or {} }))
end

-- the published data, filled in place (HairAssets holds this table)
Data.textures = { short = { id = 11, size = 256, tile = true }, straight = { id = 12, size = 1024 }, coily = { id = 13, size = 1024 },
	braid = { id = 14, size = 1024 }, cornrow = { id = 15, size = 1024 } }
Data.cap = { mesh = 20, bbox = { 0, 0.2, 0.03, 0.82, 0.86, 1.02 }, thetaMax = 2.2, tile = { 8, 4 }, points = {} }
Data.entries = {
	{ key = "afro", styles = { "Afro" }, types = { "Kinky", "Coiled", "Curly" }, cap = { cut = "full", density = 1 },
		pieces = { HairAfro01 = { mesh = 30, tex = "coily", bbox = { 0, 0.34, 0.08, 1.3, 1.1, 1.36 }, points = { 0, 0.9, 0 }, length = "volume",
			hairfx = { kind = "bounce", pivot = { 0, 0.55, 0.05 }, tip = { 0, 0.8, 0.1 } } },
			HairAfro02 = { mesh = 31, tex = "coily", bbox = { 0, 0.5, 0.1, 1.0, 0.6, 1.0 }, points = {}, length = "volume" } } },
	{ key = "fade", styles = { "High Fade", "Low Fade" }, cap = { cut = "style", density = 1 }, pieces = {} },
}

local function model()
	local head = { Name = "Head" }
	function head.IsA(_, c)
		return c == "BasePart"
	end
	return { Name = "Boxer", FindFirstChild = function(_, n)
		return n == "Head" and head or nil
	end }, head
end
local function ctx(priority, sig)
	return { priority = priority, sig = sig or "sig1", mpOptions = true, resume = function() end }
end
local function releaseAll(m)
	for _, pr in pairs(m) do
		if pr.release then
			pr.release()
		end
		if pr.part then
			pr.part:Destroy()
		end
	end
end

local afro = look(1, { style = "Afro", type = "Kinky", color = { 30, 20, 10 } })

-- selection
check("For: afro", HA.For(afro, "full", true) ~= nil)
check("For: no textures -> nil (generated low hair)", HA.For(afro, "full", false) == nil)
check("For: straight afro -> nil", HA.For(look(1, { style = "Afro", type = "Straight" }), "full", true) == nil)

-- a private build (you / your opponent / a preview)
do
	local m, head = model()
	local entry = HA.For(afro, "full", true)
	local res, result, kind = HA.Build(m, entry, afro, "full", ctx(0))
	check("build ok", res ~= nil, result)
	if res then
		local n = 0
		for _ in pairs(res) do
			n += 1
		end
		check("pieces: two cards + cap", n == 3 and res.HairCap ~= nil and res.HairAfro01 ~= nil)
		local a = res.HairAfro01
		check("record shape", a.attach == "Head" and a.attachPart == head and typeof(a.centre) == "CFrame" and a.part.Size ~= nil
			and a.mesh.nv >= 1 and a.mesh.nt == 0 and a.textured == true and a.asset == true and a.em == nil)
		check("hairfx scaled to the head", a.mesh.hairfx and a.mesh.hairfx.kind == "bounce" and math.abs(a.mesh.hairfx.pivot[2]) < 0.55)
		check("landmarks", a.mesh.landmarks and a.mesh.landmarks["HairAfro01.0"] ~= nil)
		local owners = (res.HairAfro01.img and 1 or 0) + (res.HairAfro02.img and 1 or 0)
		check("private image: one piece carries it for HairFX", owners == 1)
		check("cap has its own image", res.HairCap.img ~= nil and res.HairCap.cost > 0)
		check("texture set", a.part.TextureContent ~= nil and a.part.Transparency == 0.02)
		check("result for runJob", result.pieces.HairAfro01 and result.pieces.HairAfro01.mesh == a.mesh and result.landmarks.HairCrown ~= nil)
		check("no shared bytes for a private build", HA.SharedBytes() == 0)
		local imgs = live.images
		check("images alive: coily tint + cap", imgs == 2, imgs)
		releaseAll(res)
		check("all released", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
	end
end

-- NPCs share their tinted images by colour; the cap by look signature
do
	local m1, m2 = model(), model()
	local e = HA.For(afro, "medium", true)
	local r1 = HA.Build(m1, e, afro, "medium", ctx(2, "sigA"))
	local r2 = HA.Build(m2, e, afro, "medium", ctx(2, "sigA"))
	check("shared: images made once", live.images == 2, live.images)
	check("shared: no image handed to HairFX", r1 and r1.HairAfro01.img == nil and r1.HairAfro02.img == nil and r1.HairCap.img == nil)
	check("shared bytes counted once", HA.SharedBytes() > 0 and HA.Stats().sharedTints == 2)
	local other = look(1, { style = "Afro", type = "Kinky", color = { 200, 150, 90 } })
	local r3 = HA.Build(model(), e, other, "medium", ctx(2, "sigB"))
	check("another colour: its own tint + cap", live.images == 4, live.images)
	releaseAll(r1)
	check("still used by the second", live.images == 4)
	releaseAll(r2)
	releaseAll(r3)
	check("shared freed with the last user", live.images == 0 and HA.SharedBytes() == 0 and live.parts == 0, live.images)
end

-- a mesh that does not load: nothing kept, id marked, the entry skipped (the caller generates)
do
	failMesh[31] = "HTTP 403 (Forbidden)"
	local before = made.parts
	local res, err, kind = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("mesh failure -> nil, asset", res == nil and kind == "asset", err)
	check("nothing leaked", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
	check("failed id listed", table.find(HA.Stats().failedIds, "31") ~= nil, table.concat(HA.Stats().failedIds, ","))
	check("entry skipped after the failure", HA.For(afro, "full", true) == nil)
	check("other entries unaffected", HA.For(look(1, { style = "High Fade" }), "full", true) ~= nil)
	check("parts were attempted", made.parts > before)
	failMesh[31] = nil
	HA._failed[31] = nil
end

-- a transient texture failure: retried once after a minute
do
	-- (a new id: an id loaded once is kept as pixels and not fetched again)
	Data.textures.coily.id = 113
	failTex[113] = "HTTP 503 (Service Unavailable)"
	local res, _, kind = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("texture failure -> asset", res == nil and kind == "asset")
	check("skipped at once", HA.For(afro, "full", true) == nil)
	HA._failed[113].at -= 61
	failTex[113] = nil
	local e = HA.For(afro, "full", true)
	check("retried after 60 s", e ~= nil)
	local r2 = e and HA.Build(model(), e, afro, "full", ctx(0))
	check("loads on the retry, mark cleared", r2 ~= nil and HA._failed[113] == nil)
	if r2 then
		releaseAll(r2)
	end
	-- a permission error is not retried
	Data.textures.coily.id = 213
	failTex[213] = "Asset is not trusted for this experience"
	HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	HA._failed[213].at -= 61
	check("permanent failure not retried", HA.For(afro, "full", true) == nil)
	failTex[213] = nil
	HA._failed[213] = nil
	Data.textures.coily.id = 13
end

-- an EditableImage that cannot be made: kind "tex" (AnatomyClient pauses textures, generates), the asset not
-- blamed; a load hitting the memory budget: kind "api" (the pressure path)
do
	nilImage = true
	local res, _, kind = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	nilImage = false
	check("image creation fails -> tex", res == nil and kind == "tex", kind)
	check("not marked failed", #HA.Stats().failedIds == 0)
	check("nothing leaked (memory)", live.images == 0 and live.parts == 0)
	Data.textures.coily.id = 313
	failTex[313] = "Not enough memory: budget exceeded"
	local res2, _, kind2 = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("load over budget -> api, not marked", res2 == nil and kind2 == "api" and HA._failed[313] == nil, kind2)
	failTex[313] = nil
	Data.textures.coily.id = 13
end

-- cancelled while a mesh loads: the error goes up, nothing survives
do
	local n = 0
	local c = ctx(0)
	c.resume = function(obj)
		n += 1
		if n == 3 then
			if obj then
				obj:Destroy()
			end
			error("[AnatomyClient: build cancelled]", 0)
		end
	end
	local ok, err = pcall(HA.Build, model(), HA.For(afro, "full", true), afro, "full", c)
	check("cancel raised", not ok and tostring(err):find("cancelled", 1, true) ~= nil, err)
	check("nothing leaked (cancel)", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
end

-- the cap-only fade entry
do
	local hf = look(1, { style = "High Fade", type = "Coiled", hairline = "Line-Up" })
	local res = HA.Build(model(), HA.For(hf, "full", true), hf, "full", ctx(1))
	check("fade: cap only", res and res.HairCap and next(res, next(res)) == nil)
	if res then
		local img = res.HairCap.img
		check("cap texture size (capSize full, never above)", img and img.Size.X == 1024, img and img.Size.X)
		releaseAll(res)
	end
end

local st = HA.Stats()
print(string.format("stats: built %d failedBuilds %d entries %d usable %d", st.built, st.failedBuilds, st.entries, st.usable))
print(string.format("test_hairassets_client: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_hairassets_client failed")
end
