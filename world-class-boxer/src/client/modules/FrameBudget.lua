-- FrameBudget: the client's time-sliced builds, one queue sharing one budget a frame. A scene that would make its
-- thousands of instances in one frame (the fight venue's printed crowd rows, VenueDetail's dressing) makes them over its
-- first frames instead, BUDGET seconds of Lua a frame between all the jobs together (two builds each on a budget of its
-- own were twice the budget in the frames they shared).
--   FrameBudget.Run(fn, front) -> job   queue fn (a coroutine, first resumed on the next Heartbeat); front = ahead of
--                                       the queued jobs (what the camera sees first)
--   FrameBudget.Tick()                  inside a job: yields once this frame's budget is spent (a no-op outside a job:
--                                       the same build code runs in one go offline)
--   FrameBudget.Cancel(job)             drops a queued or running job (never resumed again)
--   FrameBudget.Busy(job?)              that job (or any) is still to finish
--   FrameBudget.Longest                 { ms, name } of the longest single slice so far (tools/sim/crowd_scene --perf)
-- A job must not yield by itself (task.wait, WaitForChild): only Tick hands the frame back.
local RunService = game:GetService("RunService")

local FrameBudget = {}

local BUDGET = 0.004 -- s of queued building a frame
FrameBudget.BUDGET = BUDGET
FrameBudget.Longest = { ms = 0 }

local queue = {}
local current = nil -- the job running now (Tick yields only inside it)
local frameEnd = 0
local conn = nil

local function step()
	frameEnd = os.clock() + BUDGET
	while queue[1] and os.clock() < frameEnd do
		local job = queue[1]
		current = job
		job.started = true
		local t0 = os.clock()
		local ok, err = coroutine.resume(job.co)
		local ms = (os.clock() - t0) * 1000
		if ms > FrameBudget.Longest.ms then
			FrameBudget.Longest = { ms = ms, name = job.name }
		end
		current = nil
		if not ok then
			warn("[FrameBudget] " .. tostring(job.name or "job") .. ":", err)
		end
		if coroutine.status(job.co) == "dead" then
			job.done = true
			local i = table.find(queue, job)
			if i then
				table.remove(queue, i)
			end
		else
			break -- (it yielded at Tick: the frame's budget is spent)
		end
	end
	if not queue[1] and conn then
		conn:Disconnect()
		conn = nil
	end
end

function FrameBudget.Run(fn, front, name)
	local job = { co = coroutine.create(fn), done = false, started = false, name = name }
	if front then
		-- (ahead of the waiting jobs, never ahead of one already started: it finishes first)
		local at = (queue[1] and queue[1].started) and 2 or 1
		table.insert(queue, math.min(at, #queue + 1), job)
	else
		table.insert(queue, job)
	end
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
	return job
end

function FrameBudget.Tick()
	if current and coroutine.running() == current.co and os.clock() >= frameEnd then
		coroutine.yield()
	end
end

function FrameBudget.Cancel(job)
	if not job then
		return
	end
	job.done = true
	local i = table.find(queue, job)
	if i then
		table.remove(queue, i)
	end
end

function FrameBudget.Busy(job)
	if job then
		return not job.done
	end
	return queue[1] ~= nil
end

return FrameBudget
