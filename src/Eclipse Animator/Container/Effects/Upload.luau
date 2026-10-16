--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Library = require("ImageLibrary")
local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local ImageUpload = {}

function ImageUpload.prompt()
	local file, editable, metadata
	local ok, asset, message = pcall(function()
		file = StudioService:PromptImportFileAsync({ "png", "jpg", "jpeg", "bmp", "tga" })
		if not file then
			return nil
		end

		editable = AssetService:CreateEditableImageAsync(Content.fromUri(file:GetTemporaryId()))
		if not editable then
			return nil, "Could not load this image. Try a smaller image or paste its asset ID."
		end

		local name = file.Name:gsub("%.[^.]+$", "")
		metadata = { name = name, width = editable.Size.X, height = editable.Size.Y }
		local result, id = AssetService:CreateAssetAsync(editable, Enum.AssetType.Image, {
			Name = name,
			Description = "Eclipse image",
		})
		if result ~= Enum.CreateAssetResult.Success then
			return nil,
				"Upload failed: " .. result.Name .. ". You can also paste an image asset ID."
		end

		return "rbxassetid://" .. tostring(id)
	end)
	if editable then
		editable:Destroy()
	end

	if file then
		file:Destroy()
	end

	if not ok then
		warn("Eclipse image upload: " .. tostring(asset))
		return nil,
			"Upload unavailable. Use the local plugin in Studio, or paste an image asset ID."
	end

	if asset then
		Library.add(asset, metadata)
	end

	return asset, message, metadata
end

return ImageUpload
