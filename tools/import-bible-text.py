#!/usr/bin/env python3
"""Extract the planned 100 passages verbatim from eBible.org's public-domain WEBP archive."""
import datetime, hashlib, json, pathlib, re, sys, urllib.request, zipfile
root=pathlib.Path(__file__).resolve().parents[1]
archive=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'.build/engwebp_vpl.zip'
url='https://ebible.org/Scriptures/engwebp_vpl.zip'
if not archive.exists():
    archive.parent.mkdir(parents=True,exist_ok=True)
    urllib.request.urlretrieve(url,archive)
catalog=json.loads((root/'docs/sombrero-v1-verse-catalog.json').read_text())
books=dict(zip(['Genesis','Numbers','Deuteronomy','Joshua','1 Samuel','2 Chronicles','Nehemiah','Job','Psalm','Proverbs','Ecclesiastes','Isaiah','Jeremiah','Lamentations','Micah','Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians','Galatians','Ephesians','Philippians','Colossians','2 Timothy','Hebrews','1 Peter'],['GEN','NUM','DEU','JOS','1SA','2CH','NEH','JOB','PSA','PRO','ECC','ISA','JER','LAM','MIC','MAT','MAR','LUK','JOH','ACT','ROM','1CO','2CO','GAL','EPH','PHI','COL','2TI','HEB','1PE']))
with zipfile.ZipFile(archive) as z:
    text=z.read('engwebp_vpl.txt').decode('utf-8-sig')
books.update({"Zephaniah":"ZEP"})
verses={}
for line in text.splitlines():
    match=re.fullmatch(r'(\S+) (\d+):(\d+) (.+)',line)
    if match: verses[(match[1],int(match[2]),int(match[3]))]=match[4]
entries=[]
for verse in catalog['verses']:
    parts=[verses[(books[verse['book']],verse['chapter'],n)] for n in range(verse['verseStart'],verse['verseEnd']+1)]
    entries.append({**verse,'text':'\n\n'.join(parts)})
assert len(entries)==100 and len({v['id'] for v in entries})==100
output={'schemaVersion':1,'translation':'World English Bible','abbreviation':'WEB','source':catalog['textSource'],'downloadURL':url,'sourceArchiveSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'retrievedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'license':'Public domain. World English Bible is a trademark of eBible.org. Text extracted verbatim; no generated or paraphrased scripture.','verses':entries}
target=root/'Sources/PetAssets/Resources/Bible/verses.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print(f'Imported {len(entries)} verified offline WEB passages')
