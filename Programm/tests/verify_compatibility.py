"""Offline checks; optional --source-dir contains user-owned original XMLs.
Does not execute the Windows installer or distribute aircraft files.
"""
import argparse, hashlib, itertools, json, re, xml.etree.ElementTree as ET
from pathlib import Path

def sha(b): return hashlib.sha256(b).hexdigest()
def select(profiles, hashes):
    return [p for p in profiles if all(hashes[n] in (p['supported_source'][n],p['expected_output'][n]) for n in hashes)]
def model_patch(data, operations):
    lines=data.decode('utf-8').splitlines(keepends=True)
    for op in operations:
        prefix='<Component ID="'+op['component_id']+'"'
        starts=[i for i,l in enumerate(lines) if l.startswith(prefix)]
        assert len(starts)==1,op['component_id']
        start=starts[0]
        cb=next(i for i in range(start,min(len(lines),start+120)) if lines[i].rstrip('\r\n')=='<CallbackCode><Code>')
        ce=next(i for i in range(cb+1,min(len(lines),cb+150)) if lines[i].rstrip('\r\n')=='</Code></CallbackCode>')
        lines[cb:ce]=[l+'\n' for l in op['new_callback_lines']]
    return ''.join(lines).encode('utf-8')
def masked(data, operations):
    text=data.decode('utf-8')
    for op in operations:
        start=text.index('<Component ID="'+op['component_id']+'"')
        cb=text.index('<CallbackCode><Code>',start)
        ce=text.index('</Code></CallbackCode>',cb)+len('</Code></CallbackCode>')
        text=text[:cb]+'__CALLBACK_'+op['component_id']+'__'+text[ce:]
    return text.encode('utf-8')
def run(root, source):
    recipe=json.loads((root/'patch_manifest.json').read_text(encoding='utf-8-sig'))
    runtime=json.loads((root/'runtime/manifest.json').read_text(encoding='utf-8-sig'))
    profiles=recipe['source_profiles'];names=list(profiles[0]['expected_output'])
    assert len(profiles)==2
    for p in profiles:
        for flags in itertools.product([False,True],repeat=3):
            hashes={n:p['expected_output' if flag else 'supported_source'][n] for n,flag in zip(names,flags)}
            assert select(profiles,hashes)==[p],(p['id'],flags)
        for n in names:
            hashes={k:p['supported_source'][k] for k in names};hashes[n]='0'*64
            assert not select(profiles,hashes)
        for target in runtime['aircraft']:
            name=target['path'].split('/')[-1]
            assert p['expected_output'][name] in target['accepted_sha256']
    original=profiles[0]
    assert original['supported_source']==recipe['supported_source']
    assert original['expected_output']==recipe['expected_output']
    generator=(root/'GeneratePayload.ps1').read_text(encoding='utf-8-sig')
    setup=(root/'SetupAndStart.ps1').read_text(encoding='utf-8-sig')
    uninstall=(root/'Uninstall.ps1').read_text(encoding='utf-8-sig')
    assert '-InstallerManifestPath' in setup
    assert '$target.sha256=[string]$profile.expected_output.$name' in generator
    assert '$matchingProfiles.Count -ne 1' in generator
    assert '$manifest.supported_source.$name' not in uninstall
    assert '$profile.supported_source.$name' in uninstall
    assert generator.index('$matchingProfiles.Count -ne 1')<generator.index('Remove-Item -LiteralPath $outDir')
    if source:
        inputs={n:(source/n).read_bytes() for n in names}
        selected=select(profiles,{n:sha(b) for n,b in inputs.items()})
        assert len(selected)==1
        p=selected[0]
        for n,b in inputs.items():
            assert sha(b)==p['supported_source'][n], 'source-dir must contain originals'
            if n=='EFA_interior.xml':
                out=model_patch(b,recipe['efa_component_callbacks'])
                assert masked(out,recipe['efa_component_callbacks'])==masked(b,recipe['efa_component_callbacks'])
            else:
                lines=b.decode('utf-8-sig').splitlines()
                ops=recipe['dep_line_ops' if n=='EF2000DEP.xml' else 'control_line_ops']
                for op in sorted(ops,key=lambda x:x['start_line'],reverse=True):
                    i=op['start_line'];lines[i:i+op['delete_count']]=op['insert_lines']
                out=b'\xef\xbb\xbf'+ ('\n'.join(lines)+ ('\n' if n=='EF2000_DEP_Control.xml' else '')).encode()
            ET.fromstring(out)
            assert sha(out)==p['expected_output'][n],n
            print(n+': generated output hash and XML verified')
        print('Model manufacturer content outside 21 target callbacks byte-preserved.')
    print('Offline profile, partial-install, unknown-state and runtime/restore checks passed.')
    print('Windows installation, SRS start and restore still require a practical test.')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);ap.add_argument('--source-dir',type=Path)
    a=ap.parse_args();run(a.root,a.source_dir)
