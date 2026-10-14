"""Allow packaging only the exact app tree whose unit, UI and widget tests passed."""
import json,os,pathlib,subprocess,urllib.request
SOURCE='2caae202aa08e3e19be5085fea54de6148eb9ae7'
RUN=38565176085
REPO='Hisabori/oncare-ios-build'
required=['Compile iPhone application','Verify system links and timer restoration first','Verify storage, backups and user flows','Verify the iOS system widget gallery']
def get(path):
 request=urllib.request.Request('https://api.github.com/repos/'+REPO+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
 with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
run=get('/actions/runs/'+str(RUN))
assert run['head_sha']==SOURCE and run['status']=='completed'
jobs=get('/actions/runs/'+str(RUN)+'/jobs')['jobs']
assert len(jobs)==1
steps={step['name']:step['conclusion'] for step in jobs[0]['steps']}
assert all(steps.get(name)=='success' for name in required),steps
subprocess.run(['git','diff','--exit-code',SOURCE,'HEAD','--','OnCare','OnCareLive','Shared','OnCareTests','OnCareUITests','project.yml'],check=True)
log=pathlib.Path('test-evidence/ios-tests.log').read_text(encoding='utf-8')
passed=[line for line in log.splitlines() if line.startswith('Test Case ') and ' passed ' in line]
assert len(passed)==91
assert not any(line.startswith('Test Case ') and ' failed ' in line for line in log.splitlines())
assert any('WidgetGalleryTests' in line for line in passed)
assert sum('MentalPublicFeedTests' in line for line in passed)==4
pathlib.Path('verified-source.txt').write_text('Tested source: '+SOURCE+'\nTests: 91 passed\nEvidence: https://github.com/'+REPO+'/actions/runs/'+str(RUN)+'\n')
print('PASS: exact tested source; 91 tests including system widget gallery')
