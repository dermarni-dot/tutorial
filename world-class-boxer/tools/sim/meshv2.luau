--!nocheck
-- meshv2.luau: reads a Roblox .mesh file, version 2.00 (what tools/hair/hairlib.py write_mesh_v2 writes and
-- Roblox accepts as a Mesh asset), into a MeshKit-like table.
--
--   local MeshV2 = require("./meshv2")
--   local m = MeshV2.Read(path)        -- or MeshV2.Decode(str)
--   -- m = { P = {x,y,z,...}, N = {...}, U = {u,v,...} (v down, as in the file), C = {r,g,b,...} (0..1) | nil,
--   --       A = {a,...} | nil, T = {a,b,c,...} (1-based), nv, nt, bbox = {cx,cy,cz, sx,sy,sz} }
--   local cx, cy, cz, sx, sy, sz = MeshV2.Bounds(m)
--
-- Layout (little endian): "version 2.00\n", then the header: u16 sizeofHeader (12, counting itself),
-- u8 sizeofVertex (36 without colours, 40 with), u8 sizeofFace (12), u32 nVerts, u32 nFaces; then nVerts
-- vertices (3 f32 position, 3 f32 normal, 2 f32 uv, 4 int8 tangent, [4 u8 rgba]); then nFaces faces of
-- 3 u32 (0-based vertex indices).
local fs = require("@lune/fs")

local MeshV2 = {}

function MeshV2.Decode(str, name)
	name = name or "mesh"
	local nl = string.find(str, "\n", 1, true)
	if not nl then
		error(name .. ": not a .mesh file (no version line)", 2)
	end
	local ver = str:sub(1, nl - 1):gsub("\r$", "")
	if ver ~= "version 2.00" then
		error(string.format("%s: unsupported %q (only version 2.00)", name, ver), 2)
	end
	local buf = buffer.fromstring(str)
	local o = nl -- (0-based offset of the header)
	local sizeofHeader = buffer.readu16(buf, o)
	local sizeofVertex = buffer.readu8(buf, o + 2)
	local sizeofFace = buffer.readu8(buf, o + 3)
	local nv = buffer.readu32(buf, o + 4)
	local nt = buffer.readu32(buf, o + 8)
	if sizeofVertex ~= 36 and sizeofVertex ~= 40 then
		error(string.format("%s: sizeofVertex %d (36 or 40 expected)", name, sizeofVertex), 2)
	end
	if sizeofFace < 12 then
		error(string.format("%s: sizeofFace %d", name, sizeofFace), 2)
	end
	local vo = o + sizeofHeader
	local fo = vo + nv * sizeofVertex
	if fo + nt * sizeofFace > buffer.len(buf) then
		error(string.format("%s: truncated (%d verts, %d faces, %d bytes)", name, nv, nt, buffer.len(buf)), 2)
	end
	local P, N, U = table.create(nv * 3), table.create(nv * 3), table.create(nv * 2)
	local hasC = sizeofVertex >= 40
	local C = hasC and table.create(nv * 3) or nil
	local A = hasC and table.create(nv) or nil
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for i = 0, nv - 1 do
		local b = vo + i * sizeofVertex
		local x, y, z = buffer.readf32(buf, b), buffer.readf32(buf, b + 4), buffer.readf32(buf, b + 8)
		P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3] = x, y, z
		N[i * 3 + 1], N[i * 3 + 2], N[i * 3 + 3] = buffer.readf32(buf, b + 12), buffer.readf32(buf, b + 16), buffer.readf32(buf, b + 20)
		U[i * 2 + 1], U[i * 2 + 2] = buffer.readf32(buf, b + 24), buffer.readf32(buf, b + 28)
		-- (b + 32: the int8 tangent, unused)
		if hasC then
			C[i * 3 + 1] = buffer.readu8(buf, b + 36) / 255
			C[i * 3 + 2] = buffer.readu8(buf, b + 37) / 255
			C[i * 3 + 3] = buffer.readu8(buf, b + 38) / 255
			A[i + 1] = buffer.readu8(buf, b + 39) / 255
		end
		x0, y0, z0 = math.min(x0, x), math.min(y0, y), math.min(z0, z)
		x1, y1, z1 = math.max(x1, x), math.max(y1, y), math.max(z1, z)
	end
	local T = table.create(nt * 3)
	for f = 0, nt - 1 do
		local b = fo + f * sizeofFace
		for k = 0, 2 do
			local idx = buffer.readu32(buf, b + k * 4)
			if idx >= nv then
				error(string.format("%s: face %d index %d out of range (%d verts)", name, f + 1, idx, nv), 2)
			end
			T[f * 3 + k + 1] = idx + 1
		end
	end
	local m = { name = name, P = P, N = N, U = U, C = C, A = A, T = T, nv = nv, nt = nt, sizeofVertex = sizeofVertex }
	if nv > 0 then
		m.bbox = { (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0 }
	else
		m.bbox = { 0, 0, 0, 0, 0, 0 }
	end
	return m
end

function MeshV2.Read(path)
	return MeshV2.Decode(fs.readFile(path), path:match("[^/]+$"))
end

-- the bounding box (centre, size): what Roblox recentres an uploaded mesh on and scales to the part's Size
function MeshV2.Bounds(m)
	local b = m.bbox
	return b[1], b[2], b[3], b[4], b[5], b[6]
end

return MeshV2
