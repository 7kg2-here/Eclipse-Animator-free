--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Geometry = {}

function Geometry.mesh(part)
	if not part:IsA("MeshPart") then
		return
	end

	local content = part.MeshContent
	if content.SourceType == Enum.ContentSourceType.Object then
		local object = content.Object
		assert(object and object:IsA("EditableMesh"), "Unsupported mesh content: " .. part.Name)
		return object
	end
end

function Geometry.capture(mesh)
	local data =
		{ Vertices = {}, Normals = {}, UVs = {}, Colors = {}, Bones = {}, Faces = {}, Weights = {} }
	for _, id in mesh:GetVertices() do
		data.Vertices[id] = mesh:GetPosition(id)
		data.Weights[id] = { mesh:GetVertexBones(id), mesh:GetVertexBoneWeights(id) }
	end

	for _, id in mesh:GetNormals() do
		data.Normals[id] = mesh:GetNormal(id)
	end

	for _, id in mesh:GetUVs() do
		data.UVs[id] = mesh:GetUV(id)
	end

	for _, id in mesh:GetColors() do
		data.Colors[id] = { mesh:GetColor(id), mesh:GetColorAlpha(id) }
	end

	for _, id in mesh:GetBones() do
		data.Bones[id] = {
			Name = mesh:GetBoneName(id),
			CFrame = mesh:GetBoneCFrame(id),
			Parent = mesh:GetBoneParent(id),
			Virtual = mesh:GetBoneIsVirtual(id),
		}
	end

	for _, id in mesh:GetFaces() do
		data.Faces[id] = {
			mesh:GetFaceVertices(id),
			mesh:GetFaceNormals(id),
			mesh:GetFaceUVs(id),
			mesh:GetFaceColors(id),
		}
	end

	return data
end

function Geometry.restore(mesh, data)
	for id, value in data.Vertices do
		mesh:SetPosition(id, value)
		mesh:SetVertexBones(id, data.Weights[id][1])
		mesh:SetVertexBoneWeights(id, data.Weights[id][2])
	end

	for id, value in data.Normals do
		mesh:SetNormal(id, value)
	end

	for id, value in data.UVs do
		mesh:SetUV(id, value)
	end

	for id, value in data.Colors do
		mesh:SetColor(id, value[1])
		mesh:SetColorAlpha(id, value[2])
	end

	for id, value in data.Bones do
		mesh:SetBoneCFrame(id, value.CFrame)
	end

	for id, value in data.Faces do
		mesh:SetFaceVertices(id, value[1])
		mesh:SetFaceNormals(id, value[2])
		mesh:SetFaceUVs(id, value[3])
		mesh:SetFaceColors(id, value[4])
	end
end

function Geometry.channels(mesh, data, callback)
	for id in data.Vertices do
		callback("Position:" .. id, function()
			return mesh:GetPosition(id)
		end, true)
		callback("Weights:" .. id, function()
			return { mesh:GetVertexBones(id), mesh:GetVertexBoneWeights(id) }
		end, false)
	end

	for id in data.Normals do
		callback("Normal:" .. id, function()
			return mesh:GetNormal(id)
		end, true)
	end

	for id in data.UVs do
		callback("UV:" .. id, function()
			return mesh:GetUV(id)
		end, true)
	end

	for id in data.Colors do
		callback("Color:" .. id, function()
			return { mesh:GetColor(id), mesh:GetColorAlpha(id) }
		end, false)
	end

	for id in data.Bones do
		callback("Bone:" .. id, function()
			return mesh:GetBoneCFrame(id)
		end, true)
	end

	for id in data.Faces do
		callback("Face:" .. id, function()
			return {
				mesh:GetFaceVertices(id),
				mesh:GetFaceNormals(id),
				mesh:GetFaceUVs(id),
				mesh:GetFaceColors(id),
			}
		end, false)
	end
end

return Geometry
