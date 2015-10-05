local Transactions = {}

function Transactions.Init()
	local self = {
		d = {}

	}

	local Pattern = {
		AllStats = "[^\n]+",
		LatestStat = "[%a%d\;]+\n$",
		ByTimestamp = "[%a%d\;]+\n",
		StringToTransaction = "[^;]+"
	}

	function self:LoadData(_data)
		self.d = _data
	end

	function self:GetAllTransactionsForItemId(itemid)
		local transactions = {}
		if self.d[itemid] ~= nil then
			local lines = string.gmatch(self.d[itemid].data, Pattern.AllStats)

			for line in lines do
				local transaction = stringToTransaction(line)
				transactions[transaction.timestamp] = transaction
			end
		end
		return transactions
	end

	function self:GetTransactionByItemIdAndTimestamp(itemid, timestamp)
		if self.d[itemid] ~= nil then
			local line = trim(string.match(self.d[itemid].data, tostring(timestamp) .. Pattern.ByTimestamp))
			if line == "" or line == nil then
				return nil
			end
			return stringToTransaction(line)
		else
			return nil
		end
	end

	function self:RemoveTimestamp(itemid, timestamp)
		self.d[itemid].data = string.gsub(self.d[itemid].data, tostring(timestamp) .. Pattern.ByTimestamp, "")
	end

	function self:SaveTransaction(itemid, stat, prepend)
		if self.d ~= nil then
			if self.d[itemid] == nil then
				self.d[itemid] = {}
				self.d[itemid].data = ""
			end
			if prepend ~= true then
				self.d[itemid].data = self.d[itemid].data .. transactionToString(stat)
			else
				self.d[itemid].data = transactionToString(stat) .. self.d[itemid].data
			end
		end
	end

	function transactionToString(transaction)
		-- concat with '..'  is very slow in lua due to immutable strings. Using a table is the recommended way for large volumes
		local t = {}
		t[1] = transaction.timestamp or ""
		t[2] = transaction.quantity or 0
		t[3] = transaction.price or 0
		t[4] = transaction.result or 0
		t[5] = '\n'

		return table.concat(t, ";")
	end

	function stringToTransaction(input)
		local t = iteratorToArray(string.gmatch(input, Pattern.StringToTransaction))
		local transaction = {}

		transaction.timestamp = tonumber(t[1])
		transaction.quantity = tonumber(t[2])
		transaction.price = tonumber(t[3])
		transaction.result = tonumber(t[4])
		return transaction
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

Apollo.RegisterPackage(Transactions, "CommodityStats:Transactions", 1, {})