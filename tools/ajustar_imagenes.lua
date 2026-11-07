-- Solo para los Word: que cada diagrama quepa completo en la página (16.5 cm x 22 cm de área útil).
-- Lee el tamaño del PNG de su encabezado y fija el ancho o el alto, lo que limite primero.
local function tam_png(ruta)
  local f = io.open(ruta, "rb")
  if not f then return nil end
  local h = f:read(24); f:close()
  if not h or #h < 24 or h:sub(2, 4) ~= "PNG" then return nil end
  local function u32(i) local a, b, c, d = h:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
  return u32(17), u32(21)
end

function Image(img)
  local ruta = img.src
  for _, base in ipairs(PANDOC_STATE.resource_path or {"."}) do
    local f = io.open(base .. "/" .. img.src, "rb")
    if f then f:close(); ruta = base .. "/" .. img.src; break end
  end
  local w, h = tam_png(ruta)
  if not w then return img end
  if h / w > 22 / 16.5 then
    img.attributes.height = "22cm"; img.attributes.width = nil
  else
    img.attributes.width = "16.5cm"; img.attributes.height = nil
  end
  return img
end
