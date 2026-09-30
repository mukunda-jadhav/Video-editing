import urllib.request, json, hashlib
from pathlib import Path
assets=Path('assets'); fonts=assets/'fonts'; models=Path('android/app/src/main/assets/models')
fonts.mkdir(parents=True,exist_ok=True); models.mkdir(parents=True,exist_ok=True)
manifest=[]
for family,name in [('notosans','StudioSans'),('lora','StudioSerif'),('robotomono','StudioMono'),('caveat','StudioScript'),('bebasneue','StudioDisplay')]:
    listing=json.load(urllib.request.urlopen('https://api.github.com/repos/google/fonts/contents/ofl/'+family))
    entry=next(e for e in listing if e['name'].endswith('.ttf') and 'Italic' not in e['name'])
    data=urllib.request.urlopen(entry['download_url']).read()
    target=fonts/(name+'.ttf');target.write_bytes(data)
    lic=next(e for e in listing if e['name']=='OFL.txt')
    (fonts/(name+'-OFL.txt')).write_bytes(urllib.request.urlopen(lic['download_url']).read())
    manifest.append({'file':str(target),'source':entry['download_url'],'sha256':hashlib.sha256(data).hexdigest(),'license':'SIL Open Font License 1.1'})
url='https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx'
data=urllib.request.urlopen(url).read()
assert hashlib.md5(data).hexdigest()=='8e83ca70e441ab06c318d82300c84806','Model checksum mismatch'
target=models/'u2netp.onnx';target.write_bytes(data)
manifest.append({'file':str(target),'source':url,'sha256':hashlib.sha256(data).hexdigest(),'md5':hashlib.md5(data).hexdigest(),'upstream':'https://github.com/xuebinqin/U-2-Net','license':'Apache-2.0 upstream model repository; ONNX conversion distributed by rembg'})
(models/'U2NET-LICENSE.txt').write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/xuebinqin/U-2-Net/master/LICENSE').read())
(models/'REMBG-LICENSE.txt').write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/danielgatis/rembg/main/LICENSE.txt').read())
Path('docs/ASSET_MANIFEST.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Downloaded and hashed bundled fonts and general-object segmentation model')
