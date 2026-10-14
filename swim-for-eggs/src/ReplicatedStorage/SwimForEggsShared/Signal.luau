--[[
	Signal  (ModuleScript)
	Location: ReplicatedStorage > SwimForEggsShared > Signal

	Tiny pure-Luau event object used for server-side communication between
	services (EggStolen, EggCarrierLost, ...). Handlers run in their own
	thread, so one erroring handler can't break the others.
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)

	return {
		Disconnect = function()
			handler.Connected = false
			local index = table.find(self._handlers, handler)
			if index then
				table.remove(self._handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	-- Clone so handlers that disconnect while firing don't skip others.
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

return Signal
