local Host = require("./host")
local H = Host.new()
local HK = H.require("HairAssetKit")
local MK = H.require("MeshKit")
local last, maxg, n = os.clock(), 0, 0
MK.SetTick(function() local t=os.clock(); local g=t-last; if g>maxg then maxg=g end; last=t; n+=1 end)
local function run(name, fn)
  last, maxg, n = os.clock(), 0, 0
  local t0=os.clock(); fn(); local tot=os.clock()-t0
  local g=os.clock()-last; if g>maxg then maxg=g end
  print(string.format("%s total %.1f ms ticks %d maxgap %.2f ms", name, tot*1000, n, maxg*1000))
end
-- grid
local gw, gh = 128, 64
local N=gw*gh
local R,G,B,C = table.create(N,0.5),table.create(N,0.4),table.create(N,0.3),table.create(N,0.8)
local grid={r=R,g=G,b=B,c=C,w=gw,h=gh}
local tile=buffer.create(256*256*4)
for i=0,256*256*4-1 do buffer.writeu8(tile,i,(i*37)%256) end
run("PaintCap1024", function() HK.PaintCap(grid,tile,256,256,8,4,1024,false,1) end)
run("PaintCap512", function() HK.PaintCap(grid,tile,256,256,8,4,512,false,1) end)
local src=buffer.create(1024*1024*4)
for i=0,1024*1024*4-1,4 do buffer.writeu32(src,i,0x80aabbcc) end
local cols={rows=1024,bands=8,cols={}}
for b=1,8 do local c=table.create(1024*3,0.5); cols.cols[b]=c end
run("Tint f1", function() HK.Tint(src,1024,1024,1,cols,false,1) end)
run("Tint f2", function() HK.Tint(src,1024,1024,2,{rows=512,bands=8,cols=cols.cols},false,1) end)
