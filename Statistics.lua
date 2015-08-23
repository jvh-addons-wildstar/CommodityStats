local Statistics = {}

function Statistics.Init()
	local self = {
		d = {}

	}

	local Pattern = {
		AllStats = "[^\n]+",
		LatestStat = "[%a%d\;]+\n$",
		ByTimestamp = "[%a%d\;]+\n"
	}

	function self:LoadData(_data)
		self.d = _data
	end

	function self:GetAllStatsForItemId(itemid)
		local stats = {}
		if self.d[itemid] ~= nil then
			local lines = string.gmatch(self.d[itemid].data, Pattern.AllStats)

			for line in lines do
				table.insert(stats, stringToStat(line))
			end
		end
		return stats
	end

	function self:GetLatestStatForItemid(itemid)
		if self.d[itemid] ~= nil then
			local line = trim(string.match(self.d[itemid].data, Pattern.LatestStat))
			if line == "" then
				return nil
			end

			return stringToStat(line)
		else
			return nil
		end
	end

	function self:GetStatByItemIdAndTimestamp(itemid, timestamp)
		if self.d[itemid] ~= nil then
			local line = trim(string.match(self.d[itemid].data, tostring(timestamp) .. Pattern.ByTimestamp))
			if line == "" or line == nil then
				return nil
			end
			return stringToStat(line)
		else
			return nil
		end
	end

	function self:UpdateStatistics(itemid, timestamp, updateditem)
		if updateditem.buyPrices.top1 == 0 and updateditem.buyPrices.top10 == 0 and updateditem.buyPrices.top50 == 0 and 
			updateditem.sellPrices.top1 == 0 and updateditem.sellPrices.top10 == 0 and updateditem.sellPrices.top50 == 0 then
			self:RemoveTimestamp(itemid, timestamp)
		else
			self.d[itemid].data = string.gsub(self.d[itemid].data, tostring(timestamp) .. Pattern.ByTimestamp, statToString(updateditem))
		end
	end

	function self:RemoveTimestamp(itemid, timestamp)
		self.d[itemid].data = string.gsub(self.d[itemid].data, tostring(timestamp) .. Pattern.ByTimestamp, "")
	end

	function self:SaveStat(itemid, stat)
		if self.d ~= nil then
			if self.d[itemid] == nil then
				self.d[itemid] = {}
				self.d[itemid].data = ""
			end
			-- make sure we don't have stats for this timestamp yet
			local existing = self:GetStatByItemIdAndTimestamp(itemid, stat.time)
			if existing == nil then
				self.d[itemid].data = self.d[itemid].data .. statToString(stat)
			end

		end
	end

	function statToString(stat)
		-- concat with '..'  is very slow in lua due to immutable strings. Using a table is the recommended way for large volumes
		local t = {}
		t[1] = stat.time
		t[2] = stat.buyOrderCount
		t[3] = stat.sellOrderCount
		t[4] = stat.buyPrices.top1
		t[5] = stat.buyPrices.top10
		t[6] = stat.buyPrices.top50
		t[7] = stat.sellPrices.top1
		t[8] = stat.sellPrices.top10
		t[9] = stat.sellPrices.top50
		t[10] = '\n'

		return table.concat(t, ";")
	end

	function stringToStat(input)
		local t = iteratorToArray(string.gmatch(input, "[^;]+"))
		local stat = {
			buyPrices = {},
			sellPrices = {}
		}

		stat.time = tonumber(t[1])
		stat.buyOrderCount = tonumber(t[2])
		stat.sellOrderCount = tonumber(t[3])
		stat.buyPrices.top1 = tonumber(t[4])
		stat.buyPrices.top10 = tonumber(t[5])
		stat.buyPrices.top50 = tonumber(t[6])
		stat.sellPrices.top1 = tonumber(t[7])
		stat.sellPrices.top10 = tonumber(t[8])
		stat.sellPrices.top50 = tonumber(t[9])
		return stat
	end

	function iteratorToArray(iterator)
		local arr = {}
				for v in iterator do
			arr[#arr + 1] = v
			end
			return arr
	end

	function trim(s)
		if s == nil then
			return nil
		end
		return s:find'^%s*$' and '' or s:match'^%s*(.*%S)'
	end
	return self
end

Apollo.RegisterPackage(Statistics, "CommodityStats:Statistics", 1, {})