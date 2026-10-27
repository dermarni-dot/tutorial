-- FrameBudget: the client's time-sliced builds, one queue sharing one budget a frame. A scene that would make its
-- thousands of instances in one frame (the fight venue's printed crowd rows, VenueDetail's dressing) makes them over its
-- first frames instead, BUDGET seconds of Lua a frame between all the jobs together (two builds each on a budget of its
-- own were twice the budget in the frames they shared).
--   FrameBudget.Run(fn, front) -> job   queue fn (a coroutine, first resumed on the next Heartbeat); front = ahead of
--                                       the queued jobs (what the camera sees first)
--   FrameBudget.Tick(reserve?)          inside a job: yields once this frame's budget is spent, or all but reserve s of
--                                       it (a no-op outside a job: the same build code runs in one go offline)
--   FrameBudget.Cancel(job)             drops a queued or running job (never resumed again)
--   FrameBudget.Finish(job)             runs the rest of a queued or running job now, in one go
--   FrameBudget.Busy(job?)              that job (or any) is still to finish
--   FrameBudget.Longest                 { ms, name } of the longest single slice so far (tools/sim/crowd_scene --perf)
--   FrameBudget.Stats                   { slices, over, recent }: slices run, those past twice the budget, the last
--                                       128 slices' ms (tests)
-- A job must not yield by itself (task.wait, WaitForChild): only Tick hands the frame back.
local RunService = game:GetService("RunService")

local FrameBudget = {}

local BUDGET = 0.004 -- s of queued building a frame
FrameBudget.BUDGET = BUDGET
FrameBudget.Longest = { ms = 0 }
-- slices run, how many ran past twice the budget, and the last 128 slices' ms (a ring: tests, a job's steps are small
-- enough to keep to its frame)
FrameBudget.Stats = { slices = 0, over = 0, recent = {} }

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
		local st = FrameBudget.Stats
		st.slices += 1
		st.recent[(st.slices - 1) % 128 + 1] = ms
		if ms > BUDGET * 2000 then
			st.over += 1
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

-- reserve (optional, seconds): yield already when less than that is left of the frame's budget (a job whose steps
-- run up to that long: a step started at the end of the budget would overrun the frame by its own length)
function FrameBudget.Tick(reserve)
	if current and coroutine.running() == current.co and os.clock() + (reserve or 0) >= frameEnd then
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

-- runs the rest of a queued or started job now, in one go (its Tick calls do not yield outside the queue's turn): a
-- build the screen needs this frame
function FrameBudget.Finish(job)
	if not job or job.done then
		return
	end
	local i = table.find(queue, job)
	if i then
		table.remove(queue, i)
	end
	job.done = true
	while coroutine.status(job.co) == "suspended" do
		local ok, err = coroutine.resume(job.co)
		if not ok then
			warn("[FrameBudget] " .. tostring(job.name or "job") .. ":", err)
			break
		end
	end
end

function FrameBudget.Busy(job)
	if job then
		return not job.done
	end
	return queue[1] ~= nil
end

return FrameBudget
