# Скачать из официального архива шаблонов Godot только веб-шаблоны (~90 МБ вместо 1,3 ГБ):
# zip читается по HTTP кусками (Range-запросы), извлекаются version.txt и web*.zip.
#   python tools/fetch_web_templates.py <папка шаблонов>   (Windows: %APPDATA%/Godot/export_templates/4.7.2.stable,
#                                                          Linux: ~/.local/share/godot/export_templates/4.7.2.stable)
import io, os, sys, urllib.request, zipfile

VERSION = "4.7.2-stable"
URL = "https://github.com/godotengine/godot/releases/download/%s/Godot_v%s_export_templates.tpz" % (VERSION, VERSION)

class Remote(io.RawIOBase):
    def __init__(self, url):
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        self.url, self.pos, self.size = r.geturl(), 0, int(r.headers["Content-Length"])
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos
    def readinto(self, b):
        if self.pos >= self.size or len(b) == 0:
            return 0
        end = min(self.size, self.pos + len(b)) - 1
        req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, end)})
        data = urllib.request.urlopen(req).read()
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)

def main(out):
    os.makedirs(out, exist_ok=True)
    z = zipfile.ZipFile(io.BufferedReader(Remote(URL), buffer_size=1 << 20))
    for info in z.infolist():
        name = os.path.basename(info.filename)
        if name == "version.txt" or name.startswith("web"):
            with open(os.path.join(out, name), "wb") as f:
                f.write(z.read(info))
            print(name, info.file_size)

if __name__ == "__main__":
    main(sys.argv[1])
