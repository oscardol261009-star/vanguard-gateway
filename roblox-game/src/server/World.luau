--!nonstrict
-- Décor du monde : ciel, atmosphère, plaza centrale, arbres.
-- Construit une seule fois au démarrage du serveur.

local Lighting = game:GetService("Lighting")

local World = {}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

local function tree(cx, cz, folder)
	local trunk = part({
		Size = Vector3.new(2, 8, 2),
		Position = Vector3.new(cx, 4, cz),
		Color = Color3.fromRGB(92, 64, 42),
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Orientation = Vector3.new(0, 0, 90)

	for i = 0, 2 do
		local cone = part({
			Size = Vector3.new(11 - i * 3, 6, 11 - i * 3),
			Position = Vector3.new(cx, 9 + i * 3.5, cz),
			Color = Color3.fromRGB(56, 122, 66),
			Material = Enum.Material.Grass,
			Parent = folder,
		})
		-- pas de vraie forme cône sur Part : on empile des blocs qui rétrécissent
	end
end

function World.build()
	-- Éclairage type fin d'après-midi, doux
	Lighting.Ambient = Color3.fromRGB(120, 120, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 160, 175)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 20
	Lighting.FogEnd = 1400
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.32
		atmo.Haze = 1.2
		atmo.Glare = 0.2
		atmo.Color = Color3.fromRGB(210, 220, 235)
		atmo.Decay = Color3.fromRGB(150, 170, 200)
		atmo.Parent = Lighting
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local sun = Instance.new("SunRaysEffect")
	sun.Intensity = 0.06
	sun.Spread = 0.6
	sun.Parent = Lighting

	-- Dossier de décor
	local deco = Instance.new("Folder")
	deco.Name = "World"
	deco.Parent = workspace

	-- Grande plaza centrale (marbre) devant les terrains
	local plaza = part({
		Name = "Plaza",
		Size = Vector3.new(90, 2, 90),
		Position = Vector3.new(120, 0.2, 40),
		Color = Color3.fromRGB(225, 225, 232),
		Material = Enum.Material.Marble,
		Parent = deco,
	})

	local ring = part({
		Size = Vector3.new(40, 2.2, 40),
		Position = Vector3.new(120, 0.4, 40),
		Color = Color3.fromRGB(120, 170, 255),
		Material = Enum.Material.SmoothPlastic,
		Parent = deco,
	})
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)

	-- Pilier central + orbe lumineux (le "totem" du hub)
	local pillar = part({
		Size = Vector3.new(6, 22, 6),
		Position = Vector3.new(120, 11, 40),
		Color = Color3.fromRGB(60, 66, 80),
		Material = Enum.Material.Slate,
		Parent = deco,
	})
	local orb = part({
		Size = Vector3.new(9, 9, 9),
		Position = Vector3.new(120, 26, 40),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Neon,
		Parent = deco,
	})
	orb.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 210, 255)
	light.Range = 60
	light.Brightness = 4
	light.Parent = orb

	-- Titre flottant du hub
	local bb = Instance.new("BillboardGui")
	bb.Adornee = orb
	bb.Size = UDim2.fromOffset(400, 90)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.AlwaysOnTop = true
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.3
	title.Text = "🏠 HOUSE RNG"
	title.Parent = bb
	bb.Parent = orb

	-- Quelques bosquets d'arbres autour
	local spots = {
		Vector3.new(60, 0, -10),
		Vector3.new(185, 0, -10),
		Vector3.new(50, 0, 90),
		Vector3.new(195, 0, 90),
		Vector3.new(120, 0, 100),
	}
	for _, s in spots do
		tree(s.X, s.Z, deco)
	end
end

return World
