local PluginManager = {}

function PluginManager.Init(cs, glog)
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
		glog:info("PLUGINMANAGER: Added search plugin with title: " .. buttonText .. ".")
	end

	function self:InitSearchWindow(selected)
		if #searchPlugins == 0 then
			glog:warn("PLUGINMANAGER: No search plugins found. Nothing to do here.")
			return
		end
		self.wndSearch = Apollo.LoadForm(cs.Xml, "wndAdvancedSearch", nil, self)
		self.wndResultList = self.wndSearch:FindChild("ResultList")
		local dropdown = self.wndSearch:FindChild("cboSearches")
		local selectedSearch = self.wndSearch:FindChild("txtSelectedSearch")
		local selectedTitle = selected or self.searchPlugins[1]

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
		local searchPlugin = self.searchPlugins[selectedTitle]
		if searchPlugin.searchCallback ~= nil then
			searchPlugin.searchCallback()
		end

		if searchPlugin.wndSearchOptions ~= nil then
			-- can't move window to a different parent, so we re-create it
			local windowName = searchPlugin.wndSearchOptions:GetName()
			glog:info("PLUGINMANAGER: Search window with name '" .. windowName .. "' exists. Adding it as child.")
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
		glog:debug("PLUGINMANAGER: Text result received")
		local result = Apollo.LoadForm(cs.Xml, "TextSearchResult", self.wndResultList, self)
		result:SetDoc(content)
	end

	return self
end


-- Register Library
Apollo.RegisterPackage(PluginManager, "CommodityStats:PluginManager", 1, {})