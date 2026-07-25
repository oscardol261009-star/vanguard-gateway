--!strict
-- Script serveur de test : confirme que Rojo synchronise bien vers Studio.
-- Si tu vois ce message dans la console (Output) de Studio, le lien fonctionne.

print("✅ Rojo est bien connecté — le code serveur tourne !")

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player: Player)
	print("👋 " .. player.Name .. " a rejoint le jeu.")
end)
