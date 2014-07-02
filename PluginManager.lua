local PluginManager = {}

function PluginManager.Init(cs)
	local self = {
		searchPlugins = {}
		wndSearch = Apollo.LoadForm(cs.Xml, "AdvancedSearch", nil, self)
	}
	Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)

	function self:AddSearch(buttonText, searchCallback, searchWindowXML, searchWindowName, tHandler)
		-- buttonText = name of the entry in the search menu
		-- searchCallback: Code that gets executed when your search is selected. Can be nil. Useful for when you don't have any search options or for setting initial parameters
		-- searchWindowXML: Xml document containing the search option window. Can be nil if there is no option window
		-- searchWindowName: name of the search option Window. Can be nil if there is no option window
		-- tHandler: eventhandler for the search option window, usually self.
		self.searchPlugins[buttonText] = {
			searchWindowXML = searchWindowXML,
			searchWindowName = searchWindowName,
			searchCallback = searchCallback,
			tHandler = tHandler
		}
		Event_FireGenericEvent("PluginManagerMessage", "Added search plugin with title: " .. buttonText .. ".")
	end

	function self:OnWindowManagementReady()
    	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndSearch, strName = "CommodityStats_Search"})
	end

	function self:InitSearchWindow(selected)
		if count(self.searchPlugins) == 0 then
			Event_FireGenericEvent("PluginManagerMessage", "No search plugins found. Nothing to do here.")
			return
		end

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
		entry:SetText(title)
		entry:SetData(title)
	end

	function self:SetActiveSearch(title)
		for i, child in ipairs(self.wndSearch:FindChild("SettingsContainer"):GetChildren()) do
			child:Destroy()
		end
		self:ClearSearchResults()
		local searchPlugin = self.searchPlugins[title]
		if searchPlugin.searchCallback ~= nil then
			searchPlugin.searchCallback()
		end
		self.wndSearch:FindChild("txtTitle"):SetText("Advanced Search - " .. title)

		if searchPlugin.searchWindowXML ~= nil and searchPlugin.searchWindowName ~= nil then
			Event_FireGenericEvent("PluginManagerMessage", "Search window with name '" .. searchPlugin.searchWindowName .. "' exists. Adding it as child.")
			Apollo.LoadForm(searchPlugin.searchWindowXML, searchPlugin.searchWindowName, self.wndSearch:FindChild("SettingsContainer"), searchPlugin.tHandler)
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
		if height ~= nil then
			local rLeft, rTop, rRight, rBottom = result:GetAnchorOffsets()
			result:SetAnchorOffsets(rLeft, rTop, rRight, rTop + height)
		end
		self.wndResultList:ArrangeChildrenVert()
	end

	function self:AddListItemSearchResult(xml, windowname, tHandler)
		Event_FireGenericEvent("PluginManagerMessage", "ListItem result received")
		local added = Apollo.LoadForm(xml, windowname, self.wndResultList, tHandler)
		self.wndResultList:ArrangeChildrenVert()
		return added
	end

	function self:OnSearchCancel( wndHandler, wndControl, eMouseButton )
    	self.wndSearch:Show(false)
	end

	function self:OnSearchSelected( wndHandler, wndControl, eMouseButton )
		local searchTitle = wndControl:GetData()
		self:SetActiveSearch(searchTitle)

		Event_FireGenericEvent("PluginManagerSearchSelected", searchTitle)
	end

	function self:GetPluginCount()
		return count(self.searchPlugins)
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