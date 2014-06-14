local PluginManager = {}

function PluginManager.Init(cs)
	local self = {
		searchPlugins = {}
	}

	function self:AddSearch(buttonText, wndSearchOptions, searchCallback, tHandler)
		-- buttonText = name of the entry in the search menu
		-- wndSearchOptions: Window containing additional filters/options for the search. Can be nil.
		-- searchCallback: Code that gets executed when your search is selected. Can be nil. Useful for when you don't have any search options
		-- tHandler: eventhandler for wndSearchOptions, usually self.
		self.searchPlugins[buttonText] = {
			wndSearchOptions = wndSearchOptions,
			searchCallback = searchCallback,
			tHandler = tHandler
		}
		Event_FireGenericEvent("PluginManagerMessage", "Added search plugin with title: " .. buttonText .. ".")
	end

	function self:InitSearchWindow(selected)
		if count(self.searchPlugins) == 0 then
			Event_FireGenericEvent("PluginManagerMessage", "No search plugins found. Nothing to do here.")
			return
		end
		self.wndSearch = Apollo.LoadForm(cs.Xml, "AdvancedSearch", nil, self)
		self.wndResultList = self.wndSearch:FindChild("ResultList")
		local dropdown = self.wndSearch:FindChild("cboSearches")
		local selectedSearch = self.wndSearch:FindChild("txtSelectedSearch")
		local selectedTitle = selected
		if not selectedTitle then
			for key, value in pairs(self.searchPlugins) do
				selectedTitle = key
				break
			end
		end

		for title, properties in pairs(self.searchPlugins) do
			self:AddDropdownEntry(dropdown, title)
		end
		dropdown:ArrangeChildrenVert()

		self.wndSearch:Show(true)
		self:SetActiveSearch(selectedTitle)
	end

	function self:AddDropdownEntry(wndTarget, title)
		local entry = Apollo.LoadForm(cs.Xml, "CustomSearchItem", wndTarget, self)
		entry:FindChild("title"):SetText(title)
		entry:SetData(title)
	end

	function self:SetActiveSearch(title)
		local searchPlugin = self.searchPlugins[title]
		if searchPlugin.searchCallback ~= nil then
			searchPlugin.searchCallback()
		end

		if searchPlugin.wndSearchOptions ~= nil then
			-- can't move window to a different parent, so we re-create it
			local windowName = searchPlugin.wndSearchOptions:GetName()
			Event_FireGenericEvent("PluginManagerMessage", "Search window with name '" .. windowName .. "' exists. Adding it as child.")
			local XmlDocument = Apollo.GetPackage("Drafto:Lib:XmlDocument-1.0").tPackage
			local tDoc = XmlDocument.CreateFromTable(searchPlugin.wndSearchOptions)
			tDoc:LoadForm(windowName, self.wndSearch:FindChild("SearchOptions"), searchPlugin.tHandler)
		end
	end

	function self:ClearSearchResults()
		for i, child in ipairs(self.wndResultList:GetChildren()) do
			child:Destroy()
		end
	end

	function self:AddTextSearchResult(content, height)
		Event_FireGenericEvent("PluginManagerMessage", "Text result received")
		local result = Apollo.LoadForm(cs.Xml, "TextSearchResult", self.wndResultList, self)
		result:SetText(content)
		self.wndResultList:ArrangeChildrenVert()
	end

	function count(dictionary)
		local count = 0
		for key, val in pairs(dictionary) do
			count = count + 1
		end
		return count
	end

	return self
end


-- Register Library
Apollo.RegisterPackage(PluginManager, "CommodityStats:PluginManager", 1, {})