extends SceneTree
## Текстуры для 3D-уровня 1: кирпич (срезы стен и перекрытий), обои комнат, полы, небо.
## Godot.exe --headless --path . --script res://tools/level1_textures.gd
## Все текстуры бесшовные (тайлятся), материалы накладывают их в мировых координатах (triplanar).

const OUT := "res://assets/textures/level1/"
const S := 512

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	brick()
	wallpaper("wall_hall", Color("d9a95b"), Color("c48a3e"), "stripes")
	wallpaper("wall_kitchen", Color("e8dcc0"), Color("8fb8a6"), "check")
	wallpaper("wall_living", Color("9aa35a"), Color("7d8743"), "damask")
	wallpaper("wall_bedroom", Color("d9a08a"), Color("c0806a"), "stripes")
	wallpaper("wall_stairs", Color("e6d3ad"), Color("cdb88d"), "damask")
	tiles("wall_bath", Color("cfe6e0"), Color("9cc4bc"), 8, 0.06)
	tiles("floor_kitchen", Color("efe3c8"), Color("2f7f7a"), 4, 0.0, true)
	tiles("floor_bath", Color("e9eef0"), Color("b8c8cf"), 8, 0.05)
	tiles("floor_balcony", Color("c86f3c"), Color("a85a2e"), 4, 0.05)
	parquet()
	carpet()
	sky()
	print("TEXTURES_OK")
	quit()

func _save(img: Image, name: String) -> void:
	img.generate_mipmaps()
	img.save_png(OUT + name + ".png")
	print("TEX ", name)

func _noise(x: int, y: int, seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0

## Кирпичная кладка: 4 кирпича в ряд, 8 рядов, перевязка со сдвигом на полкирпича.
func brick() -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var bw := S / 4
	var bh := S / 8
	var mortar := Color("cbb9a0")
	for y in S:
		var row := y / bh
		var off := (bw / 2) if row % 2 == 1 else 0
		for x in S:
			var xx := (x + off) % S
			var col := xx / bw
			var lx := xx % bw
			var ly := y % bh
			var seam := lx < 5 or ly < 5
			if seam:
				img.set_pixel(x, y, mortar.darkened(_noise(x, y, 1) * 0.12))
			else:
				var tone := _noise(col + row * 7, row, 3)
				var c := Color("a5452b").lerp(Color("c46a3f"), tone).lerp(Color("7f3221"), _noise(col, row, 9) * 0.35)
				c = c.darkened(_noise(x, y, 5) * 0.12)
				if lx < 9 or ly < 9:
					c = c.darkened(0.12)
				img.set_pixel(x, y, c)
	_save(img, "brick")

func wallpaper(name: String, base: Color, ink: Color, kind: String) -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var c := base
			match kind:
				"stripes":
					var u := x % 64
					if u < 18:
						c = ink
					elif u < 22 or (u > 40 and u < 43):
						c = base.lerp(ink, 0.5)
				"check":
					if (x % 64 < 4) or (y % 64 < 4):
						c = ink
					elif ((x / 32) + (y / 32)) % 2 == 0 and (x % 32 > 12 and x % 32 < 20 and y % 32 > 12 and y % 32 < 20):
						c = ink.lightened(0.2)
				"damask":
					var cx := (x % 128) - 64
					var cy := (y % 128) - 64
					if (y / 128) % 2 == 1:
						cx = ((x + 64) % 128) - 64
					var r := sqrt(cx * cx + cy * cy * 0.6)
					if r < 22 and abs(cx) < 30:
						c = ink
					elif r > 26 and r < 30:
						c = base.lerp(ink, 0.6)
			c = c.darkened(_noise(x, y, 11) * 0.05)
			img.set_pixel(x, y, c)
	_save(img, name)

func tiles(name: String, a: Color, b: Color, n: int, grout: float, checker := false) -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var t := S / n
	for y in S:
		for x in S:
			var c := a
			if checker and ((x / t) + (y / t)) % 2 == 1:
				c = b
			var g := int(t * grout)
			if grout > 0.0 and (x % t < g or y % t < g):
				c = b.darkened(0.1) if not checker else a.darkened(0.3)
			c = c.darkened(_noise(x / 4, y / 4, 13) * 0.05)
			img.set_pixel(x, y, c)
	_save(img, name)

## Паркет: доски разной длины и оттенка.
func parquet() -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var bh := S / 8
	for y in S:
		var row := y / bh
		var off := int(_noise(row, 0, 21) * 256)
		for x in S:
			var xx := (x + off) % S
			var plank := xx / 128
			var c := Color("b7773f").lerp(Color("8f5427"), _noise(plank, row, 23))
			c = c.darkened(sin(float(x) * 0.15 + _noise(plank, row, 7) * 10.0) * 0.04 + _noise(x, y, 25) * 0.05)
			if y % bh < 3 or xx % 128 < 3:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	_save(img, "floor_parquet")

func carpet() -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var c := Color("6b4a3a").darkened(_noise(x, y, 31) * 0.18)
			if (x / 16 + y / 16) % 2 == 0:
				c = c.lightened(0.04)
			img.set_pixel(x, y, c)
	_save(img, "floor_carpet")

func sky() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		var k := float(y) / 255.0
		var c := Color("8fc3e6").lerp(Color("e9d9b4"), k)
		for x in 256:
			var cc := c
			# силуэты домов напротив внизу
			var hgt := 150 + int(_noise(x / 40, 0, 41) * 60)
			if y > hgt:
				cc = Color("a8907a").darkened(0.1 + _noise(x / 40, 1, 43) * 0.15)
				if (x % 40 > 8 and x % 40 < 18) and (y % 24 > 6 and y % 24 < 16):
					cc = Color("f3df9a")
			img.set_pixel(x, y, cc)
	img.generate_mipmaps()
	img.save_png(OUT + "sky.png")
	print("TEX sky")
