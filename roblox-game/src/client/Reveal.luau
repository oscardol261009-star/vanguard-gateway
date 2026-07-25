--!nonstrict
-- Révélation cinématique d'un tirage, DANS LE MONDE 3D, sur le personnage.
-- Rayon de lumière, explosion de particules, aura, tremblement de caméra et
-- flash d'écran — l'intensité monte avec la rareté.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Houses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Houses"))

local player = Players.LocalPlayer
local Reveal = {}

-- Overlay plein écran pour le flash des rares
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "RevealFlash"
flashGui.IgnoreGuiInset = true
flashGui.ResetOnSpawn = false
flashGui.DisplayOrder = 50
flashGui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flash.BackgroundTransparency = 1
flash.Parent = flashGui

local function getParts()
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end
	return char, hrp, hum
end

local function cameraShake(hum, intensity, duration)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		if e >= duration or not hum.Parent then
			hum.CameraOffset = Vector3.zero
			conn:Disconnect()
			return
		end
		local decay = 1 - e / duration
		hum.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2
		) * intensity * decay
	end)
end

local function beam(hrp, color, height, width, life)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(width, height, width)
	p.CFrame = CFrame.new(hrp.Position + Vector3.new(0, height / 2 - 2, 0))
	p.Transparency = 0.25
	p.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 5
	light.Parent = p

	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad), {
		Transparency = 1,
		Size = Vector3.new(width * 3, height, width * 3),
	}):Play()
	Debris:AddItem(p, life + 0.1)
end

local function shockwave(hrp, color)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Size = Vector3.new(3, 3, 3)
	ball.CFrame = CFrame.new(hrp.Position)
	ball.Transparency = 0.2
	ball.Parent = workspace
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(40, 40, 40),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 0.6)
end

local function burst(hrp, color, count, big)
	local att = Instance.new("Attachment")
	att.Parent = hrp

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.3)
	emitter.Speed = NumberRange.new(big and 22 or 10, big and 42 or 20)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, big and 3 or 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = att
	emitter:Emit(count)

	Debris:AddItem(att, 2)
	return att, emitter
end

local function highlight(char, color, life)
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.OutlineColor = color
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char
	TweenService:Create(hl, TweenInfo.new(life), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(hl, life + 0.1)
end

local function floatingName(hrp, info, color)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 6, 0))
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(320, 90)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.62)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = color
	name.TextStrokeTransparency = 0.2
	name.Text = info.name
	name.Parent = bb

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.38)
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextStrokeTransparency = 0.4
	sub.Text = info.rarity .. "  •  1 sur " .. Houses.format(info.oneIn)
	sub.Parent = bb

	-- monte et disparaît
	TweenService:Create(anchor, TweenInfo.new(1.6, Enum.EasingStyle.Quad), {
		CFrame = CFrame.new(hrp.Position + Vector3.new(0, 12, 0)),
	}):Play()
	task.delay(1.1, function()
		TweenService:Create(name, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 1.8)
end

function Reveal.play(info)
	local char, hrp, hum = getParts()
	if not hrp then
		return
	end
	local color = Houses.RarityColor[info.rarity] or Color3.fromRGB(255, 255, 255)
	local tier = info.tier or 1

	floatingName(hrp, info, color)

	if tier <= 2 then
		-- commun : léger et rapide
		burst(hrp, color, 18, false)
		highlight(char, color, 0.6)
	elseif tier <= 3 then
		-- rare : rayon + halo
		burst(hrp, color, 40, false)
		beam(hrp, color, 70, 3, 0.7)
		highlight(char, color, 1)
	elseif tier <= 5 then
		-- épique / légendaire : onde de choc + secousse + flash
		burst(hrp, color, 90, true)
		beam(hrp, color, 90, 5, 1)
		shockwave(hrp, color)
		highlight(char, color, 1.6)
		cameraShake(hum, 0.6, 0.4)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.5
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	else
		-- mythique / secret : le grand jeu
		burst(hrp, color, 180, true)
		beam(hrp, color, 130, 8, 1.6)
		shockwave(hrp, color)
		task.delay(0.15, function()
			local _, h2 = getParts()
			if h2 then
				shockwave(h2, color)
			end
		end)
		highlight(char, color, 2.4)
		cameraShake(hum, 1.2, 0.8)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.15
		TweenService:Create(flash, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	end
end

return Reveal
