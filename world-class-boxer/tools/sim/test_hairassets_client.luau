-- tools/sim/test_hairassets_client.luau: the client loader (src/client/modules/HairAssets.lua) against a fake
-- AssetService: the piece records AnatomyClient swaps in, shared / private tinted images and their refcounts,
-- failure marking (the generated fallback), memory errors, cancellation, the transient retry. No real engine:
-- what Roblox does with the parts is not tested here.
--   lune run tools/sim/test_hairassets_client.luau
local Host = require("./host")
local Vector2 = require("@lune/roblox").Vector2
local Enum = require("@lune/roblox").Enum

-- fake engine objects -------------------------------------------------------------------------------------
local live = { parts = 0, images = 0 }
local made = { parts = 0, images = 0 }
local failMesh, failTex, nilImage, yields = {}, {}, false, 0
local texLoads = {} -- texture ids CreateEditableImageAsync was asked for
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
		texLoads[id] = true
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

-- pieces drawn with the painted cap (tex "cap": the fades' shells / fur), the cap's tile by capTile and hair
-- type, the piece's material
do
	Data.textures.shortcoil = { id = 16, size = 256, tile = true }
	Data.textures.waves = { id = 17, size = 256, tile = true }
	local fur = { mesh = 40, tex = "cap", bbox = { 0, 0.2, 0.03, 0.82, 0.86, 1.02 }, points = {}, material = "Plastic", castShadow = false }
	local shell = { mesh = 41, tex = "cap", bbox = { 0, 0.4, 0.03, 0.8, 0.5, 1.0 }, points = {}, material = "Plastic" }
	local edge = { mesh = 42, tex = "coily", bbox = { 0, 0.3, 0, 0.9, 0.6, 1.0 }, points = {}, material = "Fabric", castShadow = false }
	local nEntries = #Data.entries
	table.insert(Data.entries, { key = "buzz", styles = { "Buzz Cut" }, cap = { cut = "style", density = 1 }, pieces = { HairFur = fur } })
	table.insert(Data.entries, { key = "waves", styles = { "360 Waves" }, capTile = "waves", cap = { cut = "style", density = 1 },
		pieces = { HairFur = fur } })
	table.insert(Data.entries, { key = "shells", styles = { "Caesar Cut" }, cap = { cut = "none" }, pieces = { HairTop1 = shell, HairTop2 = shell } })
	table.insert(Data.entries, { key = "top", styles = { "High Top" }, cap = { cut = "style", density = 1 }, pieces = { HairTopEdge = edge } })

	local function loadsOf(fn)
		local before = table.clone(texLoads)
		fn()
		local new = {}
		for id in pairs(texLoads) do
			if not before[id] then
				new[#new + 1] = id
			end
		end
		table.sort(new)
		return table.concat(new, ",")
	end

	-- buzz, kinky: fur + the shared cap, both on one image painted from the shortcoil tile
	local bk = look(1, { style = "Buzz Cut", type = "Kinky" })
	local res
	local loads = loadsOf(function()
		res = HA.Build(model(), HA.For(bk, "full", true), bk, "full", ctx(0))
	end)
	check("buzz kinky built", res ~= nil and res.HairFur ~= nil and res.HairCap ~= nil)
	check("buzz kinky: the shortcoil tile loaded", loads == "16", loads)
	if res then
		check("fur draws the painted cap", res.HairFur.part.TextureContent.object == res.HairCap.part.TextureContent.object)
		check("one image (the cap), no 'cap' texture tint", live.images == 1, live.images)
		check("a private cap image carried once", (res.HairFur.img and 1 or 0) + (res.HairCap.img and 1 or 0) == 1)
		check("fur material / shadow", res.HairFur.part.Material == Enum.Material.Plastic and res.HairFur.part.CastShadow == false)
		res.HairCap.release()
		res.HairCap.part:Destroy()
		check("cap image kept while the fur uses it", live.images == 1)
		res.HairFur.release()
		res.HairFur.part:Destroy()
		check("freed with its last user", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
	end
	-- buzz, straight: the short tile
	local bs = look(1, { style = "Buzz Cut", type = "Straight" })
	loads = loadsOf(function()
		res = HA.Build(model(), HA.For(bs, "full", true), bs, "full", ctx(0))
	end)
	check("buzz straight: the short tile", res ~= nil and (loads == "11" or loads == ""), loads)
	if res then
		releaseAll(res)
	end
	-- 360 waves: the entry's capTile, whatever the type
	local wk = look(1, { style = "360 Waves", type = "Kinky" })
	loads = loadsOf(function()
		res = HA.Build(model(), HA.For(wk, "full", true), wk, "full", ctx(0))
	end)
	check("waves: the waves tile", res ~= nil and loads == "17", loads)
	if res then
		releaseAll(res)
	end
	-- shells with cap "none": no HairCap mesh, the cap still painted for them (shared by both shells)
	local sh = look(1, { style = "Caesar Cut", type = "Straight" })
	res = HA.Build(model(), HA.For(sh, "full", true), sh, "full", ctx(2, "sigS"))
	check("shells: no HairCap piece, both shells", res ~= nil and res.HairCap == nil and res.HairTop1 ~= nil and res.HairTop2 ~= nil)
	if res then
		check("shells share the painted cap", res.HairTop1.textured and res.HairTop1.part.TextureContent.object == res.HairTop2.part.TextureContent.object
			and live.images == 1, live.images)
		local r2 = HA.Build(model(), HA.For(sh, "full", true), sh, "full", ctx(2, "sigS"))
		check("an NPC with the same look shares it", r2 ~= nil and live.images == 1, live.images)
		releaseAll(res)
		check("shared cap kept for the other NPC", live.images == 1)
		if r2 then
			releaseAll(r2)
		end
		check("shells freed", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
	end
	-- the high top's edge ring: Fabric (afro builds), its shared cap from data.cap
	local ht = look(1, { style = "High Top", type = "Kinky" })
	res = HA.Build(model(), HA.For(ht, "full", true), ht, "full", ctx(0))
	check("high top: edge ring Fabric, no shadow", res ~= nil and res.HairTopEdge.part.Material == Enum.Material.Fabric
		and res.HairTopEdge.part.CastShadow == false)
	if res then
		releaseAll(res)
	end
	-- Cost: shells add the cap image once, no 'cap' texture
	local cs = HA.Cost(sh, "full", true, 0)
	check("cost: shells = one cap image", cs == 1024 * 1024 * 4, cs)
	-- a missing tile id: the short one; a missing short then: no entry
	Data.textures.shortcoil = { id = 0, size = 256, tile = true }
	loads = loadsOf(function()
		res = HA.Build(model(), HA.For(bk, "full", true), bk, "full", ctx(0))
	end)
	check("no shortcoil id: kinky buzz on the short tile", res ~= nil, loads)
	if res then
		releaseAll(res)
	end
	local short = Data.textures.short
	Data.textures.short = { id = 0, size = 256, tile = true }
	check("no tile id at all: no entry", HA.For(bk, "full", true) == nil)
	Data.textures.short = short
	-- a failed tile id skips only the looks drawn with it
	Data.textures.shortcoil = { id = 16, size = 256, tile = true }
	HA._failed[16] = { at = os.clock(), transient = false, retried = true, err = "x" }
	check("failed shortcoil: kinky buzz skipped", HA.For(bk, "full", true) == nil)
	check("failed shortcoil: straight buzz unaffected", HA.For(bs, "full", true) ~= nil)
	HA._failed[16] = nil
	for _ = #Data.entries, nEntries + 1, -1 do
		table.remove(Data.entries)
	end
	check("nothing leaked (cap users)", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
end

-- the retry: choosing an entry never uses it up; a build uses it when it really asks for that id, and an id
-- is cleared the moment it loads (not only when the whole build succeeds)
do
	Data.textures.coily.id = 413
	failTex[413] = "HTTP 503 (Service Unavailable)"
	failMesh[31] = "HTTP 503 (Service Unavailable)"
	HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0)) -- (fails on the texture: 413 marked)
	failTex[413] = nil
	check("first failure marked transient", HA._failed[413] and HA._failed[413].transient and not HA._failed[413].retried)
	HA._failed[413].at -= 61
	for _ = 1, 5 do
		HA.For(afro, "full", true)
		HA.Waiting(afro, "full", true)
	end
	check("For / Select have no side effect", HA._failed[413].retried == false)
	-- the retry: 413 loads (cleared at once) although mesh 31 then fails (first time: transient)
	local res = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("texture cleared as soon as it loaded", res == nil and HA._failed[413] == nil)
	check("the mesh that failed is marked, its retry unused", HA._failed[31] and HA._failed[31].transient and HA._failed[31].retried == false)
	-- a build that fails before reaching a due id leaves that id's retry unused
	HA._failed[31].at -= 61
	Data.textures.coily.id = 414
	failTex[414] = "HTTP 503 (Service Unavailable)"
	HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("a due id never asked keeps its retry", HA._failed[31].retried == false and HA._failed[414] ~= nil)
	failTex[414] = nil
	HA._failed[414] = nil
	-- 31's retry fails too: for the session
	HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("second failure is for good", HA._failed[31] and HA._failed[31].transient == false and HA.For(afro, "full", true) == nil)
	failMesh[31] = nil
	HA._failed[31] = nil
	Data.textures.coily.id = 13
	check("nothing leaked (retries)", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
end

-- a retry cut short is never stuck: loaded then cancelled -> cleared; failed then cancelled, or failed on the
-- device's memory (not the asset's fault) -> the retry stays unused, still due
do
	local function cancelling()
		local c = ctx(0)
		c.resume = function(obj)
			if obj then
				obj:Destroy()
			end
			error("[AnatomyClient: build cancelled]", 0)
		end
		return c
	end
	Data.textures.coily.id = 613
	HA._failed[613] = { at = os.clock() - 61, transient = true, retried = false, err = "x" }
	local ok = pcall(HA.Build, model(), HA.For(afro, "full", true), afro, "full", cancelling())
	check("loaded, then cancelled: mark cleared", not ok and HA._failed[613] == nil)
	Data.textures.coily.id = 614
	failTex[614] = "HTTP 503 (Service Unavailable)"
	HA._failed[614] = { at = os.clock() - 61, transient = true, retried = false, err = "x" }
	local ok2 = pcall(HA.Build, model(), HA.For(afro, "full", true), afro, "full", cancelling())
	check("failed, then cancelled: retry kept", not ok2 and HA._failed[614] and HA._failed[614].retried == false
		and HA.For(afro, "full", true) ~= nil)
	failTex[614] = "Not enough memory: budget exceeded"
	local r3, _, k3 = HA.Build(model(), HA.For(afro, "full", true), afro, "full", ctx(0))
	check("memory on the retry: api, retry kept", r3 == nil and k3 == "api" and HA._failed[614].retried == false
		and HA._failed[614].transient == true)
	failTex[614] = nil
	HA._failed[614] = nil
	Data.textures.coily.id = 13
	check("nothing leaked (retry cut short)", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
end

-- AnatomyClient's side of it (its internals through _test; no worker runs)
local AC = H.require("Client/AnatomyClient")
local T = AC._test
T.setHairAssets(HA)
local function rec(priority, lk)
	return { model = model(), priority = priority, look = lk or afro, sections = {}, sigs = { Hair = "s" } }
end

-- Waiting / Retry and the fallback's rebuild (evaluate's assetRetryDue): due once, never in a loop
do
	Data.textures.coily.id = 513
	failTex[513] = "request timed out"
	local job = { sig = "s", tex = true }
	local made, _, status = T.assetHair(rec(2), afro, "full", job)
	check("asset failure -> generated (nil, no stop)", made == nil and status == nil)
	local w = HA.Waiting(afro, "full", job.assetTex)
	check("Waiting: the failed id", w and w.ids[1] == 513 and w.key == "afro", w and w.ids[1])
	local st = { assetWait = w }
	check("not due before a minute", T.assetRetryDue(st) == false and st.assetWait == w and HA.Retry(w) == "wait")
	HA._failed[513].at -= 61
	check("due after a minute: the section is rebuilt", T.assetRetryDue(st) == true)
	check("checking twice uses nothing", HA._failed[513].retried == false and T.assetRetryDue(st) == true)
	-- the rebuild's retry fails again: never again, the record forgotten (no requeue loop)
	T.assetHair(rec(2), afro, "full", { sig = "s", tex = true })
	check("retry failed: never", HA.Retry(w) == "never" and HA.Waiting(afro, "full", true) == nil)
	check("never: no rebuild, record dropped", T.assetRetryDue(st) == false and st.assetWait == nil)
	-- a retry that loads: due (the rebuild draws the asset hair)
	HA._failed[513] = { at = os.clock() - 61, transient = true, retried = false, err = "x" }
	failTex[513] = nil
	local st2 = { assetWait = HA.Waiting(afro, "full", true) }
	check("due", T.assetRetryDue(st2) == true)
	local m2 = T.assetHair(rec(2), afro, "full", { sig = "s", tex = true })
	check("the rebuild draws the asset hair, mark cleared", m2 ~= nil and HA._failed[513] == nil and HA.Waiting(afro, "full", true) == nil)
	check("loaded: still 'due' for a stale record (one rebuild, then fresh)", HA.Retry(st2.assetWait) == "due")
	if m2 then
		releaseAll(m2)
	end
	Data.textures.coily.id = 13
end

-- the memory cap's estimate: the asset hair's tinted images, not the (absent) mesh bytes
do
	local you, npc = rec(0), rec(2)
	local cy = T.sectionCost("Hair", "s", "full", you)
	local cn = T.sectionCost("Hair", "s", "full", npc)
	local cl = T.sectionCost("Hair", "s", "low", you)
	print(string.format("asset hair cost: you full %.1f MB, NPC full %.1f MB, you low %.2f MB", cy / 1048576, cn / 1048576, cl / 1048576))
	-- coily 1024^2 x 4 (shared: half for an NPC) + the cap 1024^2 x 4 at full; 256^2 each at low
	check("cost: private full", cy == 1024 * 1024 * 4 * 2, cy)
	check("cost: NPC shares its tint", cn == 1024 * 1024 * 4 * 1.5, cn)
	check("cost: low", cl == 256 * 256 * 4 * 2, cl)
	local noEntry = T.sectionCost("Hair", "s", "full", rec(2, look(1, { style = "Long Hair", type = "Straight" })))
	check("no entry: the generated estimate", noEntry < 1048576 and noEntry > 0, noEntry)
	check("no rec: the generated estimate", T.sectionCost("Hair", "s", "full") == noEntry)
end

-- a first build of you / your opponent waiting preempts an asset-hair job between its serial loads
do
	local you = rec(0)
	you.sections.Head = { job = { sig = "h" } } -- (round-1 parts showing, queued: a first build)
	table.insert(T.focus, you)
	local job = { sig = "s", tex = true, first = false }
	T.setJob(job)
	local y0 = yields
	local made, _, status = T.assetHair(rec(2, look(1, { style = "Afro", type = "Kinky", color = { 90, 60, 30 } })), afro, "full", job)
	check("preempted: stop, cancelled", made == nil and status == "stop" and job.cancelled == true)
	check("preempted after one load", yields - y0 == 1, yields - y0)
	check("nothing leaked (preempted)", live.images == 0 and live.parts == 0, live.images .. " " .. live.parts)
	-- a first build itself is never preempted
	local firstJob = { sig = "s", tex = true, first = true }
	T.setJob(firstJob)
	local m2 = T.assetHair(rec(0), afro, "full", firstJob)
	check("a first build runs through", m2 ~= nil and not firstJob.cancelled)
	if m2 then
		releaseAll(m2)
	end
	table.remove(T.focus, table.find(T.focus, you))
	T.setJob(nil)
end

-- on Low (textures for the Head only on NPCs) your hair's first build already takes the asset hair
do
	AC.Settings.textureSections = { Head = true }
	local quick = T.texturesFor("Hair", nil)
	check("Low: the quick pass has no Hair textures", quick == false)
	local job = { sig = "s", tex = quick }
	local m = T.assetHair(rec(0), afro, "full", job)
	check("yours: asset hair on the first build", m ~= nil and job.tex == true)
	if m then
		releaseAll(m)
	end
	local npcJob = { sig = "s", tex = quick }
	check("an NPC's: the generated low hair", T.assetHair(rec(2), afro, "full", npcJob) == nil and not npcJob.tex)
	AC.Settings.textureSections = false
end

local st = HA.Stats()
print(string.format("stats: built %d failedBuilds %d entries %d usable %d", st.built, st.failedBuilds, st.entries, st.usable))
print(string.format("test_hairassets_client: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_hairassets_client failed")
end
