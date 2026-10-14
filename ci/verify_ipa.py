"""Verify a real unsigned iPhone app and widget against project.yml."""
from pathlib import Path
import plistlib,re,struct,sys,zipfile

ipa=Path(sys.argv[1])
spec=Path('project.yml').read_text(encoding='utf-8')
version=re.search(r'MARKETING_VERSION:\s*"([^\"]+)"',spec).group(1)
build=re.search(r'CURRENT_PROJECT_VERSION:\s*"([^\"]+)"',spec).group(1)
with zipfile.ZipFile(ipa) as archive:
 names=archive.namelist();root='Payload/OnCare.app/'
 info=plistlib.loads(archive.read(root+'Info.plist'))
 assert info['CFBundleIdentifier']=='app.oncare.personal'
 assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==build
 assert struct.unpack('<II',archive.read(root+info['CFBundleExecutable'])[:8])==(0xfeedfacf,0x0100000c)
 widgets=[p for p in names if p.endswith('.appex/Info.plist')]
 assert len(widgets)==1
 widget=plistlib.loads(archive.read(widgets[0]))
 assert widget['CFBundleShortVersionString']==version and widget['CFBundleVersion']==build
 assert widget['NSExtension']['NSExtensionPointIdentifier']=='com.apple.widgetkit-extension'
 executable=widgets[0].replace('Info.plist',widget['CFBundleExecutable'])
 assert struct.unpack('<II',archive.read(executable)[:8])==(0xfeedfacf,0x0100000c)
 assert any(p.startswith(root+'Metadata.appintents/') for p in names)
 assert not any('.xctest/' in p or p.endswith(('MedicationInterop.json','.mobileprovision')) for p in names)
 print('PASS: unsigned ARM64 app + widget, version',version,'build',build)
