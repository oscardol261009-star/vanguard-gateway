--!nonstrict
-- Construit un modèle de maison avec de vrais matériaux (bois, brique,
-- marbre, verre, or...) selon la rareté, à n'importe quelle échelle.
-- Réutilisé pour : la maison posée sur la grille du joueur (scale 1) ET
-- la miniature qui tourne sur un présentoir du marché (scale réduite).

local HouseBuilder = {}

function HouseBuilder.build(parent: Instance, cframe: CFrame, house, tier: number, scale: number, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = "House"

	local floors = math.min(tier, 6)
	local floorH = 3 * scale
	local baseW = 7 * scale

	for f = 1, floors do
		local shrink = (f - 1) * 0.7 * scale
		local w = baseW - shrink

		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(w, floorH, w)
		part.CFrame = cframe * CFrame.new(0, floorH / 2 + (f - 1) * floorH, 0)
		part.Color = house.color
		part.Material = house.wallMaterial or Enum.Material.SmoothPlastic
		part.Parent = model

		if scale >= 0.3 then
			local win = Instance.new("Part")
			win.Anchored = true
			win.CanCollide = false
			win.Size = Vector3.new(w * 0.6, floorH * 0.4, 0.15 * scale)
			win.CFrame = part.CFrame * CFrame.new(0, floorH * 0.05, -w / 2 - 0.05)
			win.Color = house.windowColor or Color3.fromRGB(190, 220, 235)
			win.Material = Enum.Material.Glass
			win.Transparency = 0.25
			win.Parent = model
		end
	end

	local topY = floors * floorH
	local shrinkTop = (floors - 1) * 0.7 * scale

	local roof = Instance.new("Part")
	roof.Anchored = true
	roof.Size = Vector3.new(baseW - shrinkTop + 1.5 * scale, 1 * scale, baseW - shrinkTop + 1.5 * scale)
	roof.CFrame = cframe * CFrame.new(0, topY + 0.5 * scale, 0)
	roof.Color = house.trimColor or Color3.fromRGB(60, 48, 42)
	roof.Material = house.roofMaterial or Enum.Material.Slate
	roof.Parent = model

	local door = Instance.new("Part")
	door.Anchored = true
	door.CanCollide = false
	door.Size = Vector3.new(2 * scale, 3 * scale, 0.4 * scale)
	door.CFrame = cframe * CFrame.new(0, 1.5 * scale, -baseW / 2)
	door.Color = Color3.fromRGB(48, 30, 20)
	door.Parent = model

	if tier >= 5 then
		local spire = Instance.new("Part")
		spire.Anchored = true
		spire.Size = Vector3.new(1 * scale, 6 * scale, 1 * scale)
		spire.CFrame = cframe * CFrame.new(0, topY + 3.5 * scale, 0)
		spire.Color = Color3.fromRGB(235, 205, 120)
		spire.Material = Enum.Material.Metal
		spire.Parent = model
	end

	if tier >= 6 then
		local orb = Instance.new("Part")
		orb.Anchored = true
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(3 * scale, 3 * scale, 3 * scale)
		orb.CFrame = cframe * CFrame.new(0, topY + 8 * scale, 0)
		orb.Color = house.color
		orb.Material = Enum.Material.Neon
		orb.Parent = model

		local light = Instance.new("PointLight")
		light.Color = house.color
		light.Range = 22 * scale
		light.Brightness = 3
		light.Parent = orb
	end

	if opts.label then
		local bb = Instance.new("BillboardGui")
		bb.Adornee = roof
		bb.Size = UDim2.fromOffset(160, opts.subtitle and 46 or 30)
		bb.StudsOffset = Vector3.new(0, 2.5 * scale + 1, 0)
		bb.AlwaysOnTop = true

		local title = Instance.new("TextLabel")
		title.Size = opts.subtitle and UDim2.fromScale(1, 0.6) or UDim2.fromScale(1, 1)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextScaled = true
		title.TextColor3 = opts.labelColor or Color3.fromRGB(255, 255, 255)
		title.TextStrokeTransparency = 0.4
		title.Text = house.name
		title.Parent = bb

		if opts.subtitle then
			local sub = Instance.new("TextLabel")
			sub.Size = UDim2.fromScale(1, 0.4)
			sub.Position = UDim2.fromScale(0, 0.6)
			sub.BackgroundTransparency = 1
			sub.Font = Enum.Font.GothamMedium
			sub.TextScaled = true
			sub.TextColor3 = Color3.fromRGB(230, 230, 230)
			sub.TextStrokeTransparency = 0.5
			sub.Text = opts.subtitle
			sub.Parent = bb
		end

		bb.Parent = roof
	end

	model.Parent = parent
	return model
end

return HouseBuilder
