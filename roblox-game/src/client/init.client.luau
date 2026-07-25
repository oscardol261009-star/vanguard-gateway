--!strict
-- Script client de test : affiche un petit message à l'écran du joueur.
-- Confirme que le code client est bien synchronisé lui aussi.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "TestRojo"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(0.4, 0.08)
label.Position = UDim2.fromScale(0.3, 0.04)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.fromRGB(20, 40, 28)
label.TextColor3 = Color3.fromRGB(120, 255, 170)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "✅ Rojo connecté !"
label.Parent = gui
