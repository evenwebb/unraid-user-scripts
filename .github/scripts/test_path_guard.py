"""Local integration smoke test with temporary Unraid-like directories."""
from pathlib import Path
import subprocess, tempfile, re, os, shutil
source = (Path(__file__).resolve().parents[2] / 'unraid-path-guard.sh').read_text()
with tempfile.TemporaryDirectory(prefix='guard-test-') as d:
    root=Path(d)
    mnt=root/'mnt'; user=mnt/'user'; appdata=mnt/'appdata'; templates=root/'templates'; state=root/'state'; bin=root/'bin'
    for p in (user,appdata/'docker',templates,bin): p.mkdir(parents=True,exist_ok=True)
    (user/'media').mkdir(); (user/'existing').mkdir(); (user/'media'/'Existing').mkdir()
    notices=root/'notifications'
    notify=bin/'notify'; notify.write_text('#!/bin/bash\nprintf "%s\\n" "notice" >> "'+str(notices)+'"\n');notify.chmod(0o755)
    docker=bin/'docker'; docker.write_text('''#!/bin/bash
case "$1" in
info) exit 0 ;;
ps) echo deadcontainer ;;
inspect) printf '/some-app\\n%s\\t/config\\n' "$MOCK_DOCKER_HOST" ;;
esac
'''); docker.chmod(0o755)
    changes={
        'MNT_ROOT':str(mnt),'USER_ROOT':str(user),'APPDATA_MOUNT':str(appdata),
        'EXPECTED_APPDATA':str(appdata/'docker'), 'FORBIDDEN_APPDATA':str(user/'appdata'),
        'TEMPLATE_DIR':str(templates),'STATE_DIR':str(state),'REQUIRE_USER_MOUNT':'0',
        'CHECK_APPDATA_MOUNT':'0', 'CHECK_UNMOUNTED_BIND_ROOTS':'0', 'LOCK_FILE':str(root/'lock'),
        'NOTIFY_SCRIPT':str(notify),'DOCKER_BIN':str(docker)
    }
    for k,v in changes.items():
        source,num=re.subn(r'^'+k+r'="[^"]*"',k+'="'+v+'"',source,flags=re.M)
        assert num==1,(k,num)
    source=source.replace('CUSTOM_WATCH_DIRS=(\n', 'CUSTOM_WATCH_DIRS=(\n    "'+str(user/'media')+'"\n')
    dest=root/'script';dest.write_text(source);dest.chmod(0o755)
    env=dict(os.environ,MOCK_DOCKER_HOST=str(appdata/'docker'/'app'),PATH=str(bin)+':'+os.environ['PATH'])

    # Invalid configuration must fail before state changes.
    bad_config=root/'bad-config.sh'
    bad_config.write_text(source.replace('CHECK_DOCKER="1"','CHECK_DOCKER="yes"'))
    bad=subprocess.run(['bash',str(bad_config)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
    assert bad.returncode==2 and 'Boolean settings must be 0 or 1' in bad.stdout,bad.stdout
    bad_watch=root/'bad-watch.sh'
    bad_watch.write_text(source.replace('    "'+str(user/'media')+'"', '    "'+str(root)+'"'))
    bad=subprocess.run(['bash',str(bad_watch)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
    assert bad.returncode==2 and 'cannot overlap STATE_DIR' in bad.stdout,bad.stdout
    linked_state=root/'linked-state'; linked_state.symlink_to(user, target_is_directory=True)
    bad_state=root/'bad-state.sh'
    bad_state.write_text(source.replace('STATE_DIR="'+str(state)+'"','STATE_DIR="'+str(linked_state)+'"'))
    bad=subprocess.run(['bash',str(bad_state)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
    assert bad.returncode==2 and 'Resolved STATE_DIR' in bad.stdout,bad.stdout
    def run(*args):
        p=subprocess.run(['bash',str(dest),*args],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
        assert p.returncode==0,(p.returncode,p.stdout)
        return p.stdout
    def count_notices(): return len(notices.read_text().splitlines()) if notices.exists() else 0
    a=run();assert '0 active concern' in a,a
    assert not notices.exists()
    assert (state/'shares.baseline').exists()
    (user/'stray-share').mkdir()
    a=run();assert 'NEW SHARE:' in a,a
    assert count_notices()==1
    a=run();assert count_notices()==1,a
    (user/'media'/'newshow').mkdir()
    a=run();assert 'NEW WATCHED SUBFOLDER' in a,a
    assert count_notices()==2
    # Accept the new folders without masking a forbidden share.
    a=run('--accept-current'); assert 'Accepted current folder snapshots' in a,a
    (user/'appdata').mkdir()
    a=run();assert 'FORBIDDEN PATH EXISTS' in a,a
    assert count_notices()==3, count_notices() # accepted folders do not notify again
    (user/'appdata').rmdir()
    has_php=shutil.which('php',path=env['PATH']) is not None
    if has_php:
        # Effective saved template path wins over the unused default.
        (templates/'my-correct.xml').write_text('<Container><Name>Correct</Name><Config Type="Path" Target="/config" Default="'+str(user/'appdata'/'abc')+'" Value="'+str(appdata/'docker'/'abc')+'"></Config></Container>')
        a=run();assert 'Saved template Correct' not in a,a
        (templates/'my-wrong.xml').write_text('<Container><Name>BadApp</Name><Config Type="Path" Default="'+str(user/'appdata'/'wrong')+'" Value="'+str(user/'appdata'/'wrong')+'"/></Container>')
        a=run(); assert 'FORBIDDEN DOCKER HOST PATH: Saved template BadApp' in a,a
        (templates/'greater-than.xml').write_text('<Container><Config Type="Path" Target="/data>" Value="'+str(user/'appdata'/'with>character')+'"/></Container>')
        a=run(); assert 'FORBIDDEN DOCKER HOST PATH: Saved template greater-than' in a,a
        (templates/'broken.xml').write_text('<Container><Config')
        a=run(); assert 'Invalid XML template: broken.xml' in a,a
    else:
        a=run(); assert 'PHP CLI unavailable' in a,a
    env['MOCK_DOCKER_HOST']=str(user/'appdata'/'plex')
    a=run(); assert 'FORBIDDEN DOCKER HOST PATH: Container some-app' in a,a
    # No actual share should have been auto-created by our script
    assert not (user/'appdata').exists()
    # Notifications cover new shares/watches, forbidden share and Docker paths.
    assert count_notices()==(6 if has_php else 4),count_notices()
    # An old folder created before first run is appropriately baselined
    assert 'existing' in (state/'shares.baseline').read_text()

    # Root-level and non-canonical binds must remain visible for review.
    if has_php:
        (templates/'root-bind.xml').write_text('<Container><Config Type="Path" Target="/" Value="/"/></Container>')
        a=run(); assert 'BROAD DOCKER BIND: Saved template root-bind: /' in a,a
        (templates/'traversal.xml').write_text('<Container><Config Type="Path" Target="/data" Value="/mnt/user/media/../appdata"/></Container>')
        a=run(); assert 'NON-CANONICAL DOCKER HOST PATH' in a,a

    # A failing `docker ps` is not mistaken for a healthy empty host.
    docker.write_text('#!/bin/bash\ncase "$1" in info) exit 0 ;; ps) exit 1 ;; esac\n')
    a=run(); assert 'Docker container listing failed' in a,a
    bad=subprocess.run(['bash',str(dest),'--unknown'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env)
    assert bad.returncode==2,bad.stdout
    print('PASS: baselines, custom watches, forbidden paths, templates, stopped containers, config validation, malformed paths, Docker failures, notifications')
