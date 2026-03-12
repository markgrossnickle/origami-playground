--!strict

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerGui = Knit.Player:WaitForChild("PlayerGui")

-- Constants
local PAGE_FOLDER = script:WaitForChild("Pages")

-- Types
type OpenPageOptions = {
	PreventSamePageClose: boolean,
}

local UIController = Knit.CreateController({
	Name = "UIController",
	Layers = {
		HUD = {
			Value = 1,
		},
		Menu = {
			Value = 2,
		},
		Prompt = {
			Value = 3,
		},
	},
})

--Private
UIController._Pages = {}
UIController._Visible = {}
function UIController:KnitInit()
	UIController.Root = PlayerGui
	UIController.StarterGuiRoot = StarterGui
	self:_collectPages()
end

function UIController:KnitStart() end

function UIController:_collectPages()
	for _, module: ModuleScript in PAGE_FOLDER:GetChildren() do
		local pageName = module.Name
		local page = Knit.GetController(pageName)
		local pageRoot = UIController.Root:FindFirstChild(pageName) or self:CreateBlankPage(pageName)
		page.Root = pageRoot
		page.Root.Enabled = false
		page.Root.ResetOnSpawn = false
		self._Pages[pageName] = page
	end
end

--Public

function UIController:CreateBlankPage(pageName: string, starterGui: boolean?): Frame
	local page = Instance.new("Frame")
	page.AnchorPoint = Vector2.new(0.5, 0.5)
	page.BackgroundTransparency = 1
	page.Name = pageName
	page.Position = UDim2.fromScale(0.5, 0.5)
	page.Size = UDim2.fromScale(1, 1)
	page.Parent = self.PagesFrame or self.Root

	--NOTE: For visibility when debugging, we also add the page to starter Gui pages frame
	if starterGui == nil or starterGui == true then
		local copy = page:Clone()
		copy.Parent = self.StarterGuiPagesFrame or self.StarterGuiRoot
	end

	return page
end

function UIController:ClosePage(pageName: string, ...): any
	local page, controller = self:GetPage(pageName)
	if self._Visible[page.DisplayOrder] ~= pageName then
		warn(`Cannot close inactive page ({pageName})`)
		return
	end
	page.Enabled = false
	self._Visible[page.DisplayOrder] = nil
	if controller.OnClose then
		return controller:OnClose(...)
	end
	return nil
end

function UIController:GetPage(pageName: string): (ScreenGui, any)
	local pageController =
		assert(self._Pages[pageName], `Page (ScreenGui or KnitController) with name: {pageName} does not exist.`)
	return pageController.Root, pageController
end

function UIController:OpenPage(pageName: string, layer: number?, options: OpenPageOptions?, ...): any
	--TODO: Select different layer if current layer is locked
	--print("OPEN", pageName, layer)

	local currentPage: string? = self._Visible[layer]
	if currentPage ~= nil then
		if currentPage == pageName then
			if options and options.PreventSamePageClose then
				return
			end
			self:ClosePage(currentPage)
			return
		end
		self:ClosePage(currentPage)
	end

	local page, controller = self:GetPage(pageName)
	page.Enabled = true
	page.DisplayOrder = layer
	self._Visible[layer] = pageName

	if controller.OnOpen then
		return controller:OnOpen(...)
	end
	return nil
end

return UIController
