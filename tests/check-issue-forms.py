#!/usr/bin/env python3
"""Catch issue and discussion form mistakes GitHub doesn't report.  An
invalid form isn't shown as an error anywhere: GitHub quietly opens a blank
issue instead, and links that fill in the form's fields stop working."""
import glob, sys
import yaml

bad = []
for path in sorted(glob.glob('.github/ISSUE_TEMPLATE/*.yml') + glob.glob('.github/DISCUSSION_TEMPLATE/*.yml')):
    if path.endswith('config.yml'):
        continue
    form = yaml.safe_load(open(path))
    # Discussion forms are named after their category and need only a body
    need = ('body',) if 'DISCUSSION_TEMPLATE' in path else ('name', 'description', 'body')
    for key in need:
        if key not in form:
            bad.append(f'{path}: missing {key}')
    ids = []
    for i, el in enumerate(form.get('body') or []):
        where = f'{path}: body[{i}]'
        if 'id' in el:
            ids.append(el['id'])
        if el.get('type') == 'dropdown':
            opts = el.get('attributes', {}).get('options') or []
            if len(set(map(str, opts))) != len(opts):
                bad.append(f'{where}: options must be unique')
            for o in opts:
                if isinstance(o, bool):
                    bad.append(f'{where}: option {o!r} is a boolean, quote it')
                elif str(o).strip().lower() == 'none':
                    bad.append(f'{where}: "None" is reserved by GitHub and can\'t be an option')
    if len(set(ids)) != len(ids):
        bad.append(f'{path}: ids must be unique')

print('\n'.join(bad) or 'Issue and discussion forms look valid.')
sys.exit(1 if bad else 0)
