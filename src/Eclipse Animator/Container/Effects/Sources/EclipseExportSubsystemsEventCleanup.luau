--!nocheck
-- riftkuro

return function(require)
	local C = {}
	local visuals = setmetatable({}, { __mode = "k" })
	function C.new()
		return {
			own = function() end,
			remember = function() end,
			update = function() end,
			finish = function() end,
		}
	end
	function C.visual(o)
		visuals[o] = true
	end
	function C.isVisual(o)
		return visuals[o] ~= nil
	end
	return C
end
